# Open Composer — embed via reverse proxy.
#
# Goal: clicking the Open Composer tile shows Open Composer *inside* OOD's own
# page — the real, live OOD navbar and footer, with Open Composer rendered in
# the middle.
#
# How it works:
#   * A reverse-proxy controller is mounted at  /pun/sys/dashboard/oc(/*path)
#     inside the dashboard. It forwards each request to the real Open Composer
#     PUN app at  /pun/sys/opencomposer/...  over the loopback through Apache
#     (https://127.0.0.1), forwarding the user's OIDC session cookie. Apache
#     validates it, sets REMOTE_USER, and its pun_proxy Lua handler routes to
#     the per-user PUN socket (which only Apache may reach). The app cannot
#     connect to that socket directly — its directory is 0700 apache-owned —
#     so going back through Apache is both necessary and how OOD proxies apps.
#   * Open Composer builds every URL from its Rack script_name, so the entire
#     app self-references the single prefix "/pun/sys/opencomposer". The proxy
#     rewrites that prefix to "/pun/sys/dashboard/oc" in every text response, so
#     links, form actions, assets and inline path vars all stay on the proxy
#     path — every page therefore stays wrapped in OOD's chrome.
#   * Open Composer's own AJAX derives its base from window.location.pathname,
#     so it follows the proxy path automatically with no JS rewriting.
#   * For HTML pages the proxy splices Open Composer's <head> assets and <body>
#     content into the dashboard's application layout (the real OOD chrome).
#     Other content types (CSS/JS/JSON/images/fonts) are streamed straight
#     through, with the prefix rewritten only for text types.

require "net/http"
require "openssl"
require "uri"
require "nokogiri"

Rails.application.config.after_initialize do
  # --- Site configuration (override via the dashboard's env file if needed) ---
  #
  # The Open Composer sys-app directory name — the "<name>" in /pun/sys/<name>.
  # Set OC_EMBED_APP_NAME if you install it under a different directory name
  # (e.g. "OpenComposer" with a capital O).
  oc_app = ENV.fetch("OC_EMBED_APP_NAME", "opencomposer")

  # Where the proxy reaches OOD's Apache for the loopback call. The defaults
  # (nil) mean: use the same host/port/scheme the browser used, connected over
  # the loopback IP 127.0.0.1 — so it does not depend on DNS or a load balancer,
  # while still presenting the real hostname for TLS SNI and the Host header so
  # name-based vhost selection on :443 picks the OOD portal vhost.
  #
  # Override these only for unusual front ends — e.g. a TLS-terminating load
  # balancer where the portal vhost actually listens on a plain-HTTP port:
  #   OC_EMBED_UPSTREAM_HOST, OC_EMBED_UPSTREAM_PORT,
  #   OC_EMBED_UPSTREAM_SCHEME (http|https), OC_EMBED_UPSTREAM_IP.
  oc_upstream_host   = ENV["OC_EMBED_UPSTREAM_HOST"]
  oc_upstream_port   = ENV["OC_EMBED_UPSTREAM_PORT"]
  oc_upstream_scheme = ENV["OC_EMBED_UPSTREAM_SCHEME"]
  oc_upstream_ip     = ENV.fetch("OC_EMBED_UPSTREAM_IP", "127.0.0.1")

  # The real Open Composer mount, and the proxy mount inside the dashboard.
  oc_upstream_prefix = "/pun/sys/#{oc_app}"
  oc_proxy_prefix    = "/pun/sys/dashboard/oc"

  # Boot-time record of what the proxy resolved, so admins can confirm the
  # OC_EMBED_* overrides actually reached this process (grep the dashboard
  # log for "[opencomposer_embed]" after a PUN restart).
  Rails.logger.info(
    "[opencomposer_embed] upstream config: " \
    "scheme=#{oc_upstream_scheme || '(request)'} " \
    "host=#{oc_upstream_host || '(request)'} " \
    "port=#{oc_upstream_port || '(request)'} " \
    "ip=#{oc_upstream_ip.presence || '(dns)'} app=#{oc_app}"
  )

  unless defined?(::OpencomposerProxyController)
    proxy = Class.new(::ApplicationController) do
      # Open Composer posts its own forms; they carry no Rails CSRF token.
      skip_forgery_protection if respond_to?(:skip_forgery_protection)

      cattr_accessor :upstream_prefix
      cattr_accessor :proxy_prefix
      cattr_accessor :app_name
      cattr_accessor :upstream_host, :upstream_port, :upstream_scheme, :upstream_ip

      # Wrapper id that Open Composer's content is placed inside; its scoped CSS
      # is confined here so it cannot reach OOD's navbar/footer.
      SCOPE_ROOT = "oc-embed-root"

      # Open Composer's script editor overlays a transparent <textarea> on a
      # <pre><code> highlight layer; they line up only if BOTH the box metrics
      # (padding/border) and the text metrics (font, line-height, letter/word
      # spacing, wrapping) are identical between the two layers. Open Composer
      # leaves the highlight's font-size to inherit, which is fine standalone
      # but not here: OOD's Bootstrap applies `pre, code { font-size: .875em }`,
      # shrinking the highlight layer to 87.5% of the textarea so the two drift
      # apart (the gap grows the further down/right the text goes). Pin every
      # metric that affects glyph advance and line advance to identical, explicit
      # values on all three layers so the overlay aligns regardless of OOD's
      # form-control/pre/code styling. Structural selectors (not the content ids)
      # cover both the script and submit editors.
      EDITOR_OVERLAY_FIX = <<~'HTML'.freeze
        <style>
        /* The highlight <pre> must have no padding (the <code> inside carries it,
           matching the textarea) or the highlighted text sits offset from the
           typed text. OOD's dashboard ships `.p-2, .app-card, pre:not(#editor)
           { padding: .5rem !important }`; its `:not(#editor)` gives it ID-level
           specificity (1,0,1) plus !important, which beats a plain class/element
           rule. Mirror the `:not(#editor)` here for equal ID-weight, so the extra
           class/element selectors win the tie (1,2,1 > 1,0,1). */
        :where(#oc-embed-root) [id$="_editor"] > pre.form-control:not(#editor) { padding: 0 !important; }
        :where(#oc-embed-root) [id$="_editor"] > textarea.form-control,
        :where(#oc-embed-root) [id$="_editor"] > pre.form-control > code {
          padding: 0.375rem 0.75rem !important;
          font-family: 'JetBrains Mono', monospace !important;
          font-size: 1rem !important;
          line-height: 1.5 !important;
          letter-spacing: normal !important;
          tab-size: 8 !important;
          white-space: pre-wrap !important;
          word-break: break-word !important;
        }
        </style>
      HTML

      # OOD's dashboard wraps page content in `#main_container.container-md`, a
      # fixed max-width centred column. Open Composer's pages are built for the
      # full viewport width (they use `.container-fluid`), so the embedded form
      # otherwise renders squeezed into the middle of the page. Lift the cap so
      # the embedded app spans the full width. This style is only injected on the
      # embedded OC pages, so every other dashboard app keeps its centred column.
      CONTENT_FULLWIDTH_FIX = <<~'HTML'.freeze
        <style>
        #main_container.container-md { max-width: none; }
        </style>
      HTML

      # Open Composer's Bootstrap is removed (see render_embedded) to avoid a
      # duplicate data-api. Its components are declarative and run on OOD's
      # Bootstrap; the only exception is one imperative bootstrap.Modal call in
      # history.js (the file-content overlay). This self-contained shim provides
      # just that, and only if no real window.bootstrap.Modal exists.
      BOOTSTRAP_MODAL_SHIM = <<~'HTML'.freeze
        <script>
        (function () {
          if (window.bootstrap && window.bootstrap.Modal) return;
          var store = new WeakMap();
          function backdrop(on) {
            var b = document.querySelector('.modal-backdrop.oc-embed-backdrop');
            if (on && !b) {
              b = document.createElement('div');
              b.className = 'modal-backdrop fade show oc-embed-backdrop';
              document.body.appendChild(b);
            } else if (!on && b) { b.remove(); }
          }
          function Modal(el) { this.el = el; }
          Modal.prototype.show = function () {
            var el = this.el, self = this;
            el.style.display = 'block';
            el.classList.add('show');
            el.removeAttribute('aria-hidden');
            document.body.classList.add('modal-open');
            backdrop(true);
            this._click = function (e) {
              if (e.target === el || (e.target.closest && e.target.closest('[data-bs-dismiss="modal"]'))) self.hide();
            };
            this._key = function (e) { if (e.key === 'Escape') self.hide(); };
            el.addEventListener('click', this._click);
            document.addEventListener('keydown', this._key);
          };
          Modal.prototype.hide = function () {
            var el = this.el;
            el.style.display = 'none';
            el.classList.remove('show');
            el.setAttribute('aria-hidden', 'true');
            document.body.classList.remove('modal-open');
            backdrop(false);
            if (this._click) el.removeEventListener('click', this._click);
            if (this._key) document.removeEventListener('keydown', this._key);
          };
          window.bootstrap = window.bootstrap || {};
          window.bootstrap.Modal = {
            getOrCreateInstance: function (el) {
              var i = store.get(el);
              if (!i) { i = new Modal(el); store.set(el, i); }
              return i;
            }
          };
        })();
        </script>
      HTML

      def show
        sub = params[:oc_path].to_s
        sub = "/#{sub}" unless sub.start_with?("/")
        path = "#{self.class.upstream_prefix}#{sub}"
        path = "#{path}?#{request.query_string}" if request.query_string.present?

        res = forward(path)

        # Relay redirects to the browser, rewriting the Location back onto the
        # proxy path so navigation stays wrapped in OOD's chrome.
        if res["location"].present?
          loc = rewrite(res["location"])
          redirect_to(loc, allow_other_host: true, status: res.code.to_i)
          return
        end

        ctype = res["content-type"].to_s
        body  = res.body.to_s

        if ctype.include?("text/html")
          render_embedded(rewrite(body))
        elsif text_type?(ctype)
          send_data rewrite(body), type: ctype, disposition: "inline"
        else
          send_data body,
                    type: ctype.presence || "application/octet-stream",
                    disposition: "inline"
        end
      end

      private

      # Forward the current request to the Open Composer PUN app via Apache,
      # authenticated with the browser's forwarded session cookie.
      #
      # By default this connects to the same host/port/scheme the browser used,
      # but over the loopback IP (no DNS / load-balancer dependency), while
      # presenting the real hostname for TLS SNI + the Host header so Apache
      # selects the OOD portal vhost (important on :443 hosts that serve several
      # name-based vhosts — connecting to a bare IP would hit the wrong one).
      def forward(path)
        host   = self.class.upstream_host   || request.host
        port   = (self.class.upstream_port  || request.port).to_i
        scheme = self.class.upstream_scheme || request.scheme

        http = Net::HTTP.new(host, port)
        http.ipaddr = self.class.upstream_ip if self.class.upstream_ip.present? && http.respond_to?(:ipaddr=)
        http.use_ssl      = false # http.use_ssl      = (scheme == "https")
        http.verify_mode  = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
        http.open_timeout = 10
        http.read_timeout = 120

        klass = request.post? ? Net::HTTP::Post : Net::HTTP::Get
        req   = klass.new(path)

        # Forward the OIDC session cookie so Apache authenticates the call and
        # sets REMOTE_USER; mirror Host so Apache's host check passes and Open
        # Composer derives the right base_url for any absolute links.
        req["Cookie"] = request.headers["Cookie"] if request.headers["Cookie"]
        req["Host"]   = request.host_with_port

        # Present the browser's original scheme/host/port so the upstream
        # behaves as if this call came through the front end. Behind a
        # TLS-offloading load balancer the loopback hop may be plain HTTP;
        # without these headers Apache's https rewrites / OIDC URL building /
        # the app's scheme detection would treat the call as http.
        req["X-Forwarded-Proto"] = request.scheme
        req["X-Forwarded-Host"]  = request.host_with_port
        req["X-Forwarded-Port"]  = request.port.to_s
        %w[Accept Accept-Language X-Requested-With].each do |h|
          v = request.headers[h]
          req[h] = v if v.present?
        end

        if request.post?
          req.body = request.raw_post
          ct = request.headers["Content-Type"]
          req["Content-Type"] = ct if ct.present?
        end

        http.request(req)
      end

      # Splice Open Composer's head + body into the dashboard layout, which
      # renders the live OOD navbar and footer around it.
      def render_embedded(html)
        doc  = Nokogiri::HTML(html)
        head = doc.at_css("head")
        head&.at_css("title")&.remove # keep the dashboard's own <title>

        # The OOD dashboard already loads Bootstrap. Drop Open Composer's
        # duplicate Bootstrap so it can't clash with OOD's chrome:
        #  * JS — two copies both bind the click data-api, so an OOD navbar
        #    dropdown gets toggled open by one and shut by the other and never
        #    appears (a tiny shim below covers OC's one imperative Modal call).
        #  * CSS — a second Bootstrap stylesheet loaded after OOD's overrides
        #    OOD's themed navbar/footer.
        # OOD's single Bootstrap then styles and drives OC's components, which
        # are declarative (data-bs-*).
        doc.css("script[src]").each do |s|
          s.remove if s["src"].to_s.match?(/bootstrap[^"']*\.js/)
        end
        doc.css("link[href]").each do |l|
          l.remove if l["href"].to_s.match?(%r{bootstrap@[\d.]+/dist/css/bootstrap})
        end

        # Scope Open Composer's own inline CSS to its container so its global
        # rules (a, .nav-link, .btn-primary, .footer a, body, …) cannot restyle
        # OOD's navbar/footer, which sit outside that container.
        head_html = (head ? head.inner_html : "").gsub(%r{(<style[^>]*>)(.*?)(</style>)}m) do
          "#{$1}#{scope_css($2)}#{$3}"
        end

        body_html = doc.at_css("body") ? doc.at_css("body").inner_html : html
        @oc_head = (BOOTSTRAP_MODAL_SHIM + head_html + EDITOR_OVERLAY_FIX + CONTENT_FULLWIDTH_FIX).html_safe
        @oc_body = %(<div id="#{SCOPE_ROOT}">#{body_html}</div>).html_safe
        render template: "apps/opencomposer_embed", layout: "application"
      end

      # Prefix every selector in a (flat, no-at-rule) CSS string so it only
      # applies within the embed container. `body`/`html` selectors map to the
      # container itself. The prefix is wrapped in :where() so it contributes
      # ZERO specificity — Open Composer's cascade is preserved exactly as it is
      # standalone (e.g. its plain `a { color }` rule stays lower-specificity
      # than Bootstrap's `.nav-link`/`.btn`, so the navbar text follows
      # navbar_text_color and buttons keep their own colors).
      def scope_css(css)
        root = ":where(##{SCOPE_ROOT})"
        css.gsub(%r{/\*.*?\*/}m, "").gsub(/([^{}]+)\{([^{}]*)\}/m) do
          selectors, decls = Regexp.last_match(1), Regexp.last_match(2)
          scoped = selectors.split(",").map(&:strip).reject(&:empty?).map do |sel|
            if sel =~ /\A(?:html|body)\b(.*)\z/m
              "#{root}#{Regexp.last_match(1)}"
            else
              "#{root} #{sel}"
            end
          end.join(", ")
          "#{scoped} { #{decls.strip} }"
        end
      end

      def rewrite(text)
        text.to_s.gsub(self.class.upstream_prefix, self.class.proxy_prefix)
      end

      def text_type?(ctype)
        ctype.match?(%r{\A(text/|application/(javascript|json|xml|.*\+xml|x-javascript))})
      end
    end

    proxy.upstream_prefix = oc_upstream_prefix
    proxy.proxy_prefix    = oc_proxy_prefix
    proxy.app_name        = oc_app
    proxy.upstream_host   = oc_upstream_host
    proxy.upstream_port   = oc_upstream_port
    proxy.upstream_scheme = oc_upstream_scheme
    proxy.upstream_ip     = oc_upstream_ip
    Object.const_set(:OpencomposerProxyController, proxy)
  end

  # Mount the proxy. format: false keeps asset extensions (.css/.js) inside the
  # captured path instead of being parsed as a response format.
  Rails.application.routes.append do
    match "/oc(/*oc_path)",
          to: "opencomposer_proxy#show",
          via: %i[get post],
          format: false,
          defaults: { oc_path: "" }
  end
  Rails.application.reload_routes!

  # Clicking the Open Composer tile lands on the embedded proxy instead of
  # redirecting straight to the bare PUN app.
  AppsController.prepend(Module.new do
    define_method(:show) do
      if params[:name] == OpencomposerProxyController.app_name && params[:type] == "sys"
        redirect_to "#{OpencomposerProxyController.proxy_prefix}/"
      else
        super()
      end
    end
  end)
end
