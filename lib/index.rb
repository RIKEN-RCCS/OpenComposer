require "uri"

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
                URI.join(url, "no_image_square.jpg")
              elsif valid_url?(icon)
                icon
              else
                tmp_icon_path = File.join("/", @apps_dir, dirname, icon)
                icon_local_path = File.join(Dir.pwd, tmp_icon_path)

                if File.exist?(icon_local_path)
                  File.join(@script_name, tmp_icon_path)
                elsif icon.start_with?("bi-", "fa-")
                  is_bi_or_fa_icon = true
                  nil
                else
                  URI.join(url, "no_image_square.jpg")
                end
              end
  
  [is_bi_or_fa_icon, icon_path]
end

helpers do
  # Create an HTML snippet for displaying a thumbnail image.
  # The image source can either be a URL, a bootstrap icon, a fontawesome icon or a local path.
  # If the icon is not provided. a placeholder image is used.
  def output_thumbnail(dirname, name, icon)
    is_bi_or_fa_icon, icon_path = get_icon_path(dirname, icon)

    # Use the text-reset class to prevent color changes when using font awesome icons
    html = <<~HTML
      <div class="col text-center">
        <div class="d-flex flex-column h-100 align-items-center">
          <div class="flex-grow-1 d-flex align-items-center">
            <a href="#{@script_name}/#{dirname}" class="stretched-link position-relative text-reset">
HTML
    width = @conf['thumbnail_width']
    if is_bi_or_fa_icon
      html << "<i class=\"#{icon}\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    else
      html << "<img src=\"#{icon_path}\" class=\"img-thumbnail\" width=\"#{width}\" height=\"100\" alt=\"#{name}\">"
    end
    html << <<~HTML
             </a>
           </div>
        #{name}
        </div>
      </div>
    HTML
  end
end
