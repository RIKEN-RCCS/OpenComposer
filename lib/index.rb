require "uri"

# Group manifests by category for the page listings.
#
# A manifest's "category" may be a single string or a list. Grouping on the raw
# value would make a list its own group whose heading renders as a Ruby array
# literal, so expand each entry instead: an application listed under several
# categories appears under each of them. Category order follows the order the
# manifests are already sorted in, so the caller's sort is preserved.
def group_manifests_by_category(manifests)
  manifests.each_with_object({}) do |m, groups|
    Array(m.category).each { |cat| (groups[cat] ||= []) << m }
  end
end

# Return true if the provided icon is in a valid URL format.
def valid_url?(icon)
  return false if icon.nil? || (!icon.start_with?("http://") && !icon.start_with?("https://"))

  uri = URI.parse(icon)
  return uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
rescue URI::InvalidURIError => e
  halt 500, e.message
end

# Resolves the appropriate icon path based on the provided icon and directory name.
def get_icon_path(dirname, icon)
  is_bi_or_fa_icon = false # Bootstrap icon or Font Awesome icon
  icon_path = if icon.nil?
                "#{@script_name}/app_default.svg"
              elsif valid_url?(icon)
                icon
              else
                tmp_icon_path = File.join("/", @apps_dir, dirname, icon)
                icon_local_path = File.join(APP_ROOT, tmp_icon_path)

                if File.exist?(icon_local_path)
                  File.join(@script_name, tmp_icon_path)
                elsif icon.start_with?("bi-", "fa-")
                  is_bi_or_fa_icon = true
                  nil
                else
                  "#{@script_name}/app_default.svg"
                end
              end

  [is_bi_or_fa_icon, icon_path]
end

helpers do
  # Create an HTML snippet for a user template card with a delete button.
  def output_template_thumbnail(slug, name, description, app_path, icon)
    width      = @conf['thumbnail_width']
    safe_nm    = ERB::Util.h(name)
    safe_dsc   = ERB::Util.h(description.to_s)
    enc_slug   = ERB::Util.u(slug)
    safe_cfm   = name.gsub("\\", "\\\\\\\\").gsub("'", "\\'")
    safe_app   = ERB::Util.h(app_path.to_s)
    desc_html  = description.to_s.strip.empty? ? "" :
      "<div class=\"small text-muted mt-1\" style=\"word-break:break-word;\">#{safe_dsc}</div>"

    raw_icon  = icon.to_s
    icon_html = if raw_icon.start_with?("bi-", "fa-")
      "<i class=\"#{ERB::Util.h(raw_icon)}\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    elsif raw_icon.start_with?("http://", "https://")
      "<img src=\"#{ERB::Util.h(raw_icon)}\" class=\"img-thumbnail\" loading=\"lazy\" decoding=\"async\" width=\"#{width}\" height=\"100\" alt=\"#{safe_nm}\">"
    elsif !raw_icon.empty?
      url_path = if app_path.to_s.start_with?("_generic/")
        gd  = @conf["generic_apps_dir"] || "./generic_apps"
        sub = app_path.sub(/\A_generic\//, "")
        local = File.join(APP_ROOT, gd, sub, raw_icon)
        File.exist?(local) ? File.join(@script_name, "/", gd, sub, raw_icon) : nil
      else
        tp    = File.join("/", @apps_dir, app_path, raw_icon)
        local = File.join(APP_ROOT, tp)
        File.exist?(local) ? File.join(@script_name, tp) : nil
      end
      url_path ? "<img src=\"#{ERB::Util.h(url_path)}\" class=\"img-thumbnail\" loading=\"lazy\" decoding=\"async\" width=\"#{width}\" height=\"100\" alt=\"#{safe_nm}\">" :
                 "<img src=\"#{ERB::Util.h("#{@script_name}/app_default.svg".to_s)}\" class=\"img-thumbnail\" loading=\"lazy\" decoding=\"async\" width=\"#{width}\" height=\"100\" alt=\"#{safe_nm}\">"
    else
      "<img src=\"#{ERB::Util.h("#{@script_name}/app_default.svg".to_s)}\" class=\"img-thumbnail\" loading=\"lazy\" decoding=\"async\" width=\"#{width}\" height=\"100\" alt=\"#{safe_nm}\">"
    end

    <<~HTML
      <div class="col text-center oc-tmpl-card" data-slug="#{enc_slug}" data-name="#{safe_nm.downcase}" data-desc="#{safe_dsc.downcase}">
        <div class="d-flex flex-column h-100 align-items-center position-relative">
          <div class="position-absolute top-0 end-0 d-flex gap-1" style="z-index:5;">
            <button type="button" class="btn btn-sm btn-link text-secondary p-0 lh-1"
                    title="Edit template"
                    data-bs-toggle="modal" data-bs-target="#modal-rename-template"
                    data-slug="#{enc_slug}" data-name="#{safe_nm}" data-desc="#{safe_dsc}">
              <i class="bi bi-pencil-fill fs-6"></i>
            </button>
            <form method="post" action="#{@script_name}/templates/#{enc_slug}/delete">
              <button type="submit" class="btn btn-sm btn-link text-danger p-0 lh-1"
                      title="Delete template"
                      onclick="return confirm('Delete template \\'#{safe_cfm}\\'?')">
                <i class="bi bi-x-circle-fill fs-6"></i>
              </button>
            </form>
          </div>
          <div class="flex-grow-1 d-flex align-items-center">
            <a href="#{@script_name}/#{safe_app}?template=#{enc_slug}" class="stretched-link position-relative text-reset">
              #{icon_html}
            </a>
          </div>
          #{safe_nm}
          #{desc_html}
        </div>
      </div>
    HTML
  end

  # A single row in the All Templates / New Script list for an application
  # manifest: category/GPU badges, name and description, linking to the app's
  # form. href_suffix is appended to the link (e.g. "?path=…&new_template=1").
  def output_all_template_row(m, href_suffix = "")
    badges = Array(m.category).map do |cat|
      color = (@conf['category_badge_colors'] || {}).fetch(cat, nil) || '#6c757d'
      %(<span class="badge me-1" style="background-color:#{ERB::Util.h(color)}; color:#fff;">#{ERB::Util.h(cat)}</span>)
    end.join
    if @gpu_names.include?(m.name.to_s.downcase) || Array(m.tags).map(&:downcase).include?("gpu")
      badges += %(<span class="badge me-1" style="background-color:#000; color:#fff;">GPU</span>)
    end
    desc = (m.description && m.description.to_s.strip != '') ? %(<div class="small text-muted">#{ERB::Util.h(m.description)}</div>) : ''
    <<~HTML
      <a href="#{@script_name}/#{ERB::Util.h(m.dirname)}#{href_suffix}" class="d-block text-decoration-none py-2 px-3 border-bottom oc-all-item"
         data-name="#{ERB::Util.h(m.name.to_s.downcase)}" data-desc="#{ERB::Util.h(m.description.to_s.downcase)}" data-cat="#{ERB::Util.h(Array(m.category).join(' ').downcase)}">
        <div>#{badges}<span class="fw-semibold">#{ERB::Util.h(m.name)}</span></div>
        #{desc}
      </a>
    HTML
  end

  # A single row in the All Templates list for a user's saved custom template,
  # tagged "My Template" and linking to its app form pre-filled (?template=slug).
  def output_custom_template_row(t)
    desc = t["description"].to_s.strip.empty? ? '' : %(<div class="small text-muted">#{ERB::Util.h(t["description"])}</div>)
    href = "#{@script_name}/#{ERB::Util.h(t["app_path"])}?template=#{ERB::Util.u(t["slug"])}"
    <<~HTML
      <a href="#{href}" class="d-block text-decoration-none py-2 px-3 border-bottom oc-all-item"
         data-name="#{ERB::Util.h(t["name"].to_s.downcase)}" data-desc="#{ERB::Util.h(t["description"].to_s.downcase)}" data-cat="my template">
        <div><span class="badge me-1" style="background-color:#6f42c1; color:#fff;">My Template</span><span class="fw-semibold">#{ERB::Util.h(t["name"])}</span></div>
        #{desc}
      </a>
    HTML
  end

  # Create an HTML snippet for displaying a thumbnail image.
  # The image source can either be a URL, a bootstrap icon, a fontawesome icon or a local path.
  # If the icon is not provided. a placeholder image is used.
  def output_thumbnail(dirname, name, icon, href_suffix = "")
    is_bi_or_fa_icon, icon_path = get_icon_path(dirname, icon)

    # Use the text-reset class to prevent color changes when using font awesome icons
    html = <<~HTML
      <div class="col text-center oc-app-card" data-name="#{ERB::Util.h(name.to_s.downcase)}">
        <div class="d-flex flex-column h-100 align-items-center">
          <div class="flex-grow-1 d-flex align-items-center">
            <a href="#{@script_name}/#{dirname}#{href_suffix}" class="stretched-link position-relative text-reset">
HTML
    width = @conf['thumbnail_width']
    if is_bi_or_fa_icon
      html << "<i class=\"#{ERB::Util.h(icon)}\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    else
      html << "<img src=\"#{icon_path}\" class=\"img-thumbnail\" loading=\"lazy\" decoding=\"async\" width=\"#{width}\" height=\"100\" alt=\"#{name}\">"
    end
    html << <<~HTML
             </a>
           </div>
        #{name}
        </div>
      </div>
    HTML
  end

  # Compact pill link for the small home format (no icon).
  def output_small_app_link(dirname, name)
    safe_nm = ERB::Util.h(name)
    %(<a href="#{@script_name}/#{dirname}" class="btn btn-sm btn-outline-secondary py-0 px-2 oc-small-app-link">#{safe_nm}</a>)
  end

  # Like output_thumbnail but resolves icons from generic_apps_dir and links to /_generic/{dirname}.
  def output_generic_thumbnail(dirname, name, icon, href_suffix = "")
    generic_apps_dir = @conf["generic_apps_dir"] || "./generic_apps"
    is_bi_or_fa_icon = false
    icon_s = icon.to_s
    icon_path = if icon_s.empty?
                  "#{@script_name}/app_default.svg"
                elsif valid_url?(icon_s)
                  icon_s
                elsif icon_s.start_with?("bi-", "fa-")
                  is_bi_or_fa_icon = true
                  nil
                else
                  local = File.join(APP_ROOT, generic_apps_dir, dirname, icon_s)
                  File.exist?(local) ? File.join(@script_name, "_generic_icon", dirname, icon_s) : "#{@script_name}/app_default.svg"
                end

    width = @conf['thumbnail_width']
    icon_html = if is_bi_or_fa_icon
                  "<i class=\"#{ERB::Util.h(icon_s)}\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
                else
                  "<img src=\"#{ERB::Util.h(icon_path.to_s)}\" class=\"img-thumbnail\" loading=\"lazy\" decoding=\"async\" width=\"#{width}\" height=\"100\" alt=\"#{ERB::Util.h(name)}\">"
                end

    <<~HTML
      <div class="col text-center oc-app-card" data-name="#{ERB::Util.h(name.to_s.downcase)}">
        <div class="d-flex flex-column h-100 align-items-center">
          <div class="flex-grow-1 d-flex align-items-center">
            <a href="#{@script_name}/_generic/#{dirname}#{href_suffix}" class="stretched-link position-relative text-reset">
              #{icon_html}
            </a>
          </div>
          #{ERB::Util.h(name)}
        </div>
      </div>
    HTML
  end
end
