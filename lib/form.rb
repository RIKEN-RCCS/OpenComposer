helpers do
  # If flag is true, returns "active"; otherwise returns nil.
  def active?(flag)
    return "active" if flag
  end

  # Output a label with HTML label tags and an optional asterisk of label.
  def output_label_with_label_tag(key, value, i)
    label = if value['label'].dig(1).is_a?(Array)
              value['label'][1].length > i ? value['label'][1][i] : ""
            elsif value['label']&.is_a?(Array)
              value['label'].length > i ? value['label'][i] : ""
            else
              value['label']
            end

    required = if value['required']&.is_a?(Array)
                 value['required'][i].to_s == "true" || false
               else
                 value['required'].to_s == "true"
               end
    
    label = if label.nil? || label.empty?
              required ? "*" : ""
            elsif required
              label + "*"
            else
              label
            end
    
    id = i.nil? ? key : "#{key}_#{i+1}"
    style = label.empty? ? "display: none;" : ""
    
    # The values of data-label= and data-required= are used when changing the label with set-required of the dynamic form widget.
    return "<label id=\"label_#{id}\" style=\"#{style}\" class=\"fw-semibold form-label mb-1\" data-label=\"#{label}\" data-required=\"#{required}\" for=\"#{id}\">#{label}</label>\n"
  end
  
  # Output a label with HTML span tags and an optional asterisk of label.
  def output_label_with_span_tag(key, value)
    label = if !value['label'].is_a?(Array)
              value['label']
            else
              value['label'][0]
            end
    
    required = value['required'].to_s == "true"

    label = if label.nil? || label.empty?
              required ? "*" : ""
            elsif required
              label + "*"
            else
              label
            end

    style = label.empty? ? "display: none;" : ""
    
    # The values of data-label= and data-required= are used when changing the label with set-required of the dynamic form widget.
    return "<div id=\"label_#{key}\" style=\"#{style}\" class=\"fw-semibold mb-1\" data-label=\"#{label}\" data-required=\"#{required}\">#{label}</div>\n"
  end

  # Output attributes.
  def output_attribute(key, value, i, attr)
    return "" unless value.key?(attr)
    
    attr_value = value[attr].is_a?(Array) ? value[attr][i] : value[attr]
    if attr_value
      return attr == 'required' ? " required " : " #{attr}=\"#{escape_html(attr_value)}\" "
    else
      return ""
    end
  end

  # Output a help text.
  def output_help(key, value, i = nil)
    help = if value['help'].is_a?(Array)
             value['help'].length > i ? value['help'][i] : ''
           elsif value['help'].nil?
             ""
           else
             value['help']
           end
    
    id = i.nil? ? key : "#{key}_#{i+1}"
    style = help.empty? ? "display: none;" : ""
    return "<p id=\"help_#{id}\" style=\"#{style}\" class=\"form-text mb-0\">#{help.to_s.chomp}</p>\n"
  end

  # Output style to add an indent.
  def add_indent_style(value)
    value.key?('indent') && (1..5).include?(value['indent'].to_i) ? "padding-left: #{value['indent'].to_i * 1.2}em;" : ""
  end
  
  # Output a number, text, or email widget.
  def output_number_text_email_html(key, value)
    size = value.key?('size') ? value['size'] : 1
    html  = "<div class=\"row g-1 gx-3\">\n"
    if !value['label'].is_a?(Array) || value['label'].dig(1).is_a?(Array)
      html += output_label_with_span_tag(key, value)
    end
    
    size.times do |i|
      id = value.key?('size') ? "#{key}_#{i+1}" : key
      if value['label'].is_a?(Array) || value['required'].is_a?(Array)
        html += "<div class=\"col\">\n"
        html += output_label_with_label_tag(key, value, i)
      else
        html += "<div class=\"col mt-0\">\n"
      end
      html += "<input type=\"#{value['widget']}\" class=\"form-control\" tabindex=\"#{@table_index}\" id=\"#{id}\" name=\"#{id}\" "
      html += output_attribute(key, value, i, 'min')  if value['widget'] == "number"
      html += output_attribute(key, value, i, 'max')  if value['widget'] == "number"
      html += output_attribute(key, value, i, 'step') if value['widget'] == "number"
      html += output_attribute(key, value, i, 'value')
      html += output_attribute(key, value, i, 'required')
      html += "oninput=\"ocForm.updateValues('#{id}')\">\n"
      html += output_help(key, value, i) if value['help'].is_a?(Array)
      html += "</div>\n"
      @table_index += 1
    end
    
    html += output_help(key, value) unless value['help'].is_a?(Array)
    
    return html + "</div>\n"
  end

  # Normalize calc(expr) or calc(expr, dp) to calc(expr, dp, OC_ROUNDING_ROUND)
  def normalize_calc_args(expr)
    args = expr.split(/\s*,\s*/)
    case args.length
    when 1
      "#{args[0]}, 0, OC_ROUNDING_ROUND"
    when 2
      "#{args[0]}, #{args[1]}, OC_ROUNDING_ROUND"
    else
      expr
    end
  end

  # Wraps an identifier for string interpolation.
  # Constants starting with "OC_ROUNDING_" are returned as-is.
  # Other identifiers are converted to "#{name}" (or "#{:name}" if prefixed).
  def wrap_ident(colon, name)
    return name if name.start_with?("OC_ROUNDING_")
    "\#{#{colon ? ':' : ''}#{name}}"
  end
  
  # Output a JavaScript code based on a given yml, line in script, and matches data.
  def output_script_js(form, line, app_name, dir_name)
    # Remove leading and trailing whitespace(e.g. #{ time_1  } -> #{time_1})
    line.gsub!(/#\{\s*(.*?)\s*\}/, '#{\1}')
    
    # Substitute constant valiables
    line.gsub!(/\#\{OC_APP_NAME\}/,         app_name)
    line.gsub!(/\#\{:OC_APP_NAME\}/,        app_name)
    line.gsub!(/\#\{OC_DIR_NAME\}/,         dir_name)
    line.gsub!(/\#\{:OC_DIR_NAME\}/,        dir_name)
    line.gsub!(/\#\{OC_SCRIPT_LOCATION\}/,  "\#\{#{HEADER_SCRIPT_LOCATION}\}")
    line.gsub!(/\#\{:OC_SCRIPT_LOCATION\}/, "\#\{:#{HEADER_SCRIPT_LOCATION}\}")
    line.gsub!(/\#\{OC_CLUSTER_NAME\}/,     "\#\{#{HEADER_CLUSTER_NAME}\}")
    line.gsub!(/\#\{:OC_CLUSTER_NAME\}/,    "\#\{:#{HEADER_CLUSTER_NAME}\}")
    line.gsub!(/\#\{OC_SCRIPT_NAME\}/,      "\#\{#{HEADER_SCRIPT_NAME}\}")
    line.gsub!(/\#\{:OC_SCRIPT_NAME\}/,     "\#\{:#{HEADER_SCRIPT_NAME}\}")
    line.gsub!(/\#\{OC_JOB_NAME\}/,         "\#\{#{HEADER_JOB_NAME}\}")
    line.gsub!(/\#\{:OC_JOB_NAME\}/,        "\#\{:#{HEADER_JOB_NAME}\}")

    # Escape backslashes (`\`) by replacing each `\` with `\\`.
    # This ensures the backslashes are properly interpreted in JavaScript strings.
    line.gsub!("\\", "\\\\\\\\")
    
    # Escape single quotes (`'`) by replacing each `'` with `\'`.
    # This prevents syntax errors in JavaScript when embedding the string.
    line.gsub!("'", "\\\\'")

    matches = line.scan(/\#\{.+?\}/)
    return "  selectedValues.push(\'#{line}\');\n" if matches.empty?

    keys = matches.flat_map do |str|
      inner = str[2..-2] # "#{time_1}" -> "time_1"

      if inner =~ /\A(?:zeropadding|calc|dirname|basename)\(/
        args = inner[/\((.*)\)/, 1] || "" # time_1 + time_2 - :time_3 * 2
 
        if inner.start_with?("zeropadding(") && args.lstrip.start_with?("calc(")
          calc_args = args.lstrip[/calc\((.*)\)/, 1] || ""
          next calc_args.scan(/:[A-Za-z_]\w*|[A-Za-z_]\w*/)
        end
        
        args.scan(/:[A-Za-z_]\w*|[A-Za-z_]\w*/) # ["time_1", "time_2", ":time_3"]
      else
        inner
      end
    end

    line = line.gsub(/\#\{(zeropadding|calc|dirname|basename)\((.*?)\)\}/) do
      func = Regexp.last_match(1)       # "zeropadding", "calc", "dirname", "basename"
      expr = Regexp.last_match(2) || "" # e.g. "time_1 * time_2, 2"
      expr = normalize_calc_args(expr) if func == "calc"

      # --- special case: zeropadding(calc(...), N) ---
      if func == "zeropadding" && expr =~ /\A\s*calc\((.*)\)\s*,\s*(.*)\z/
        calc_expr = Regexp.last_match(1)           # "time_1 * time_2"
        calc_expr = normalize_calc_args(calc_expr) # "time_1 * time_2, 0, OC_ROUNDING_ROUND"
        z_second_arg = Regexp.last_match(2).strip  # "2"
  
        # Expand only inside calc(...)
        replaced_calc_expr = calc_expr.gsub(/(:)?([A-Za-z_]\w*)/) do
          colon = Regexp.last_match(1)
          name  = Regexp.last_match(2)
          wrap_ident(colon, name)
        end
        
        next "\#{zeropadding(calc(#{replaced_calc_expr}), #{z_second_arg})}"
      end

      # --- normal case: calc(...), dirname(...), basename(...), zeropadding(...) ---
      replaced = expr.gsub(/(:)?([A-Za-z_]\w*)/) do
        colon = Regexp.last_match(1)
        name  = Regexp.last_match(2)
        wrap_ident(colon, name)
      end

      "\#\{#{func}(#{replaced})\}"
    end

    exist_keys    = []
    widgets       = []
    can_hide      = []
    separators    = []
    keys.each do |key|
      if key.start_with?(':')
        can_hide << "true"
        key = key.delete_prefix(':')
      else
        can_hide << "false"
      end
      
      base_key, _, suffix = key.rpartition("_")
      if form.key?(key)
        exist_keys << key
        widgets << form[key]["widget"]
        separators << form[key]["separator"]
      elsif form.key?(base_key) && suffix =~ /^\d+$/
        exist_keys << key
        widgets << form[base_key]["widget"]
        separators << form[base_key]["separator"]
      else
        can_hide.pop()
      end
    end

    if exist_keys.length > 0
      # Convert to JavaScript array
      keys_array          = "['" + exist_keys.join("', '") + "']"
      widgets_array       = "['" + widgets.join("', '") + "']"
      can_hide_array      = "["  + can_hide.map { |r| r }.join(", ") + "]"
      separators_array    = "["  + separators.map { |s| s.nil? ? 'null'  : "'#{s}'" }.join(", ") + "]"

      return "  ocForm.showLine(selectedValues, '#{line}', #{keys_array}, #{widgets_array}, #{can_hide_array}, #{separators_array});\n"
    else
      return "  selectedValues.push('#{line}');\n"
    end
  end

  # Output a select widget.
  def output_select_html(key, value)
    return "" if value['options'].nil?
    
    html = output_label_with_span_tag(key, value)
    html += "<select tabindex=\"#{@table_index}\" id=\"#{key}\" name=\"#{key}\" class=\"form-select\" onchange=\"ocForm.updateValues('#{key}')\">\n"
    @table_index += 1
    
    value['options'].each_with_index do |v, i|
      # The data-value is used in Script Content (ocForm.getValue() in form.js)
      # If v[1] is not defined, v[0] is used instead.
      data_value = v[1].nil? ? v[0] : v[1]
      selected = value['value'].to_s == v[0].to_s ? 'selected' : ''
      escaped_data = escape_html(data_value)
      escaped_item = escape_html(v[0])
      html += "<option id=\"#{key}_#{i+1}\" data-value='#{escaped_data}' value='#{escaped_item}' #{selected}>#{escaped_item}</option>\n"
    end
    
    html + "</select>\n" + output_help(key, value) 
  end

  # Output a multi-select widget.
  def output_multi_select_html(key, value)
    return "" if value['options'].nil?
    
    search_input_id      = key
    suggestions_list_id  = "suggestionsList_#{key}"
    add_button_id        = "addButton_#{key}"
    valid_suggestions_id = "validSuggestions_#{key}"
    selected_items_id    = "selectedItems_#{key}"
    hidden_values_id     = "hiddenValues_#{key}"

    required = value['required'].to_s == "true" ? "true" : "false"
    html  = output_label_with_span_tag(key, value)
    html += "<ul id='#{valid_suggestions_id}' style='display: none;'>\n"
    value['options'].each do |i|
      data_value = i[1].nil? ? i[0] : i[1]
      escaped_data = escape_html(data_value)
      escaped_item = escape_html(i[0])
      html += "<li data-value='#{escaped_data}'>#{escaped_item}</li>\n"
    end
    html += "</ul>\n"

    html += <<~HTML
    <div class="input-group">
      <input type="text" tabindex=\"#{@table_index}\" class="form-control" id="#{key}" onkeydown="ocForm.handleKeyDown(event, '#{key}')" oninput="ocForm.showSuggestions('#{key}')" onfocus="ocForm.showSuggestions('#{key}', true)" onblur="ocForm.hideSuggestions('#{key}')" data-required=\"#{required}\">
      <button class="btn btn-dark" id="#{add_button_id}" disabled onclick="ocForm.addSelectedItem('#{key}')">add</button>
    </div>
    <ul class="list-group position-absolute w-100" id="#{suggestions_list_id}"></ul>
    <div id="#{selected_items_id}" class="d-flex flex-wrap gap-2 mt-2"></div>
    <div id="#{hidden_values_id}"></div>
    HTML
    @table_index += 1
    
    return html + output_help(key, value)
  end

  # Output a JavaScript code to prepopulate the multi-select input with existing values.
  def output_multi_select_js(key, value)
    return "" unless value.key?('value') && !value['value'].to_s.empty?
    
    values = value['value'].is_a?(Array) ? value['value'] : [value['value']]
    js = "  const textarea = document.createElement('textarea');\n"
    values.each do |v|
      js += "  textarea.innerHTML = '#{escape_html(v)}';\n"
      js += "  ocForm.getSearchInput('#{key}').value = textarea.value;\n"
      js += "  ocForm.addSelectedItem('#{key}', false);\n"
    end
    
    return js
  end

  # Output a radio widget.
  def output_radio_html(key, value)
    return "" if value['options'].nil?
    
    is_horizontal = value['direction'] == "horizontal"
    required = value['required'].to_s == "true" ? "required" : ""
    html = output_label_with_span_tag(key, value)
    value['options'].each_with_index do |v, i|
      div_class = is_horizontal ? "form-check form-check-inline me-4 mt-2" : "form-check mt-2"
      checked = value['value'].to_s == v[0].to_s ? "checked" : ""
      data_value = v[1].nil? ? v[0] : v[1]
      escaped_data = escape_html(data_value)
      escaped_item = escape_html(v[0])
      id = "#{key}_#{i+1}"
      html += <<-HTML
      <div class="#{div_class}">
        <input type="radio" tabindex="#{@table_index}" id="#{id}" data-value='#{escaped_data}' value="#{escaped_item}" name="#{key}" class="form-check-input" #{checked} #{required} oninput="ocForm.updateValues('#{id}')">
        <label class="form-check-label" for="#{id}">#{escaped_item}</label>
      </div>
      HTML
    end

    @table_index += 1
    return html + output_help(key, value)
  end

  # Output a checkbox widget.
  def output_checkbox_html(key, value)
    return "" if value['options'].nil?
    
    is_horizontal = value['direction'] == "horizontal"
    html = output_label_with_span_tag(key, value)
    value['options'].each_with_index do |v, i|
      div_class = is_horizontal ? "form-check form-check-inline me-4 mt-2" : "form-check mt-2"
      if value.key?('value')
        checked = Array(value['value']).map(&:to_s).include?(v[0].to_s)
      else
        checked = false
      end
      required = if value['required'].is_a?(Array)
                   value['required'][i].to_s == "true" || false
                 else
                   false
                 end
      data_value = v[1].nil? ? v[0]: v[1]
      escaped_data = escape_html(data_value)
      escaped_item = escape_html(v[0])
      item_label = "#{escaped_item}#{required ? '*' : ''}"
      id = "#{key}_#{i+1}"
      html += <<-HTML
      <div class="#{div_class}">
        <input type="checkbox" tabindex="#{@table_index}" data-value='#{escaped_data}' value="#{escaped_item}" id="#{id}" name="#{id}" class="form-check-input" #{'checked' if checked} #{'required' if required} oninput="ocForm.updateValues('#{id}')">
        <label class="form-check-label" data-label="#{item_label}" data-required="#{required}" id="label_#{id}" for="#{id}">#{item_label}</label>
      </div>
      HTML

      @table_index += 1
    end
    
    return html + output_help(key, value)
  end

  # Output a JavaScript code to prepopulate the checkbox widget.
  # If "required: true", the submit button cannot be pressed.
  def output_checkbox_js(key, value)
    return !value['required'].is_a?(Array) && value['required'].to_s == "true" ? "  ocForm.validateCheckboxForSubmit('#{key}');" : ""
  end
  
  # Output a path widget.
  def output_path_html(key, value)
    favorites = value['favorites'] ? value['favorites'].select { |path| File.exist?(path) } : []
    current_value = escape_html(value['value']) || ""
    current_path = escape_html(value['value']) || Dir.home
    current_path = Dir.home unless File.exist?(current_path.to_s)
    current_path = (File.directory?(current_path) && !current_path.end_with?('/')) ? "#{current_path}/" : current_path
    show_files   = value['show_files'].nil? ? true : value['show_files']
    required     = value['required'].to_s == "true" ? "required" : ""
    html  = output_label_with_span_tag(key, value)
    html += <<~HTML
    <div class="d-flex align-items-center">
      <input type="text" tabindex="#{@table_index}" value="#{current_value}" id="#{key}" name="#{key}" #{required} class="form-control mt-0" oninput="ocForm.updateValues('#{key}')">
      <button class="btn btn-dark mt-0 text-nowrap" data-bs-toggle="modal" data-bs-target="#modal-#{key}" tabindex="-1" onclick="ocForm.loadFiles('#{@script_name}', '#{current_path}', '#{key}', #{show_files}, '#{Dir.home}', true); return false;">Select Path</button>
    </div>
    <div class="modal" id="modal-#{key}">
      <div class="modal-dialog modal-lg" style="overflow-y: initial !important;">
        <div class="modal-content">
          <div class="modal-body" style="max-height: 80vh;overflow-y: auto;">
            <div class="container-fluid">
              <div class="row">
    HTML

    if favorites.any?
      html += <<~HTML
              <div class='col-5'>
                <div>Favorites</div>
                  <table class='table table-bordered table-hover table-sm mt-1'>
                    <tbody onclick="ocForm.handleRowClick(event, '#{key}', #{show_files}, '#{@script_name}', '#{Dir.home}')">
      HTML
    
      favorites.each do |path|
        logo = File.file?(path) ? "&#x1f4c4;" : "&#x1F4C1;"
        html += "<tr><td class='text-center'>#{logo}</td><td><a href='#' data-path='#{path}' onclick=\"ocForm.loadFiles('#{@script_name}', '#{path}', '#{key}', #{show_files}, '#{Dir.home}', false);\">#{path}</a></td></tr>\n"
      end

      html += <<~HTML
                    </tbody>
                  </table>
                </div> <!-- <div class='col-5'> -->
      HTML
    end

    html += <<~HTML
                <div class="col">
                  <table class='table table-primary table-bordered table-sm'>
                    <tbody><tr><td id="oc-modal-data-#{key}" data-path="#{current_path}"></td></tr></tbody>
                  </table>
                  <div class="d-flex justify-content-end mb-3 table-sm">
                    <div class="form-check form-check-inline me-4 mt-1">
                      <input type="checkbox" value="checked" id="oc-modal-checkbox-#{key}" class="form-check-input" oninput="ocForm.hideHidden('#{key}')" checked>
                      <label class="form-check-label text-dark" for="oc-modal-checkbox-#{key}">Hide hidden</label>
                    </div>
                    <div class="input-group input-group-sm" style="max-width: 250px;">
                      <span class="input-group-text">Filter</span>
                      <input type="text" class="form-control" aria-label="Filter" id="oc-modal-filter-#{key}" oninput="ocForm.filterRows('#{key}')">
                    </div>
                  </div>
                  <table class='table table-bordered table-hover table-sm'>
                    <thead>
                       <tr class='table-secondary'>
                        <th class='text-center' style="white-space: nowrap; width: 1%;">Type
                          <div class="d-inline">
                            <button tabindex="-1" style="font-size:8px;" class="btn btn-sm btn-outline-primary p-1" id="oc-modal-button-#{key}-0" onclick="ocForm.toggleSort('#{key}', 0); return false;" data-direction="desc">&#9660;</button>
                          </div>
                        </th>
                        <th class='text-center'>Name
                          <div class="d-inline">
                            <button tabindex="-1" style="font-size:8px;" class="btn btn-sm btn-outline-primary p-1" id="oc-modal-button-#{key}-1" onclick="ocForm.toggleSort('#{key}', 1); return false;" data-direction="desc">&#9660;</button>
                          </div>
                        </th>
                      </tr>
                    </thead>
                    <tbody id="oc-modal-tbody-#{key}" onclick="ocForm.handleRowClick(event, '#{key}', #{show_files}, '#{@script_name}', '#{Dir.home}')"></tbody>
                   </table>
                </div> <!-- <div class="col"> -->
              </div> <!-- <div class="row"> -->
            </div> <!-- <div class="container-fluid"> -->
          </div> <!-- <div class="modal-body"> -->
          <div class="modal-footer">
            <button class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1" type="button">Close</button>
            <button class="btn btn-primary" data-bs-dismiss="modal" tabindex="-1" type="button" onclick="ocForm.updatePath('#{key}')">Select Path</button>
          </div>
        </div> <!-- <div class="modal-content"> -->
      </div> <!-- <div class="modal-dialog"> -->
    </div> <!-- <div class="modal"> -->
    HTML

    @table_index += 1
    return html + output_help(key, value)
  end

  # Parse options to extract specific attributes like min, max, step, label, or value.
  def get_oc_set_attrs(options, form)
    elements = []
    return elements if options.nil? || options.empty?

    options.each do |option|
      next unless option.is_a?(Hash)

      key, value = option.first
      attr = case key
             when /^set-min-/      then "min"
             when /^set-max-/      then "max"
             when /^set-step-/     then "step"
             when /^set-label-/    then "label"
             when /^set-value-/    then "value"
             when /^set-required-/ then "required"
             when /^set-help-/     then "help"
             else next
             end

      # Check value
      if (["min", "max", "step"].include?(attr) && !value.is_a?(Numeric)) ||
         (attr == "required" && ![true, false].include?(value))
        halt 500, "#{option} is invalid."
      end
      
      form.each do |k, v|
        if key =~ /^set-#{attr}-#{k}$/
          elements.push({"attr" => attr, "key" => k, "value" => value})
        elsif ["number", "text", "email"].include?(v["widget"]) && key =~ /^set-#{attr}-#{k}_\d+$/
          num = key.split('_').last.to_i
          elements.push({"attr" => attr, "key" => k, "value" => value, "num" => num})
        elsif v["widget"] == "checkbox" && attr == "required"
          v['options'].each_with_index do |_option, i|
            if key =~ /^set-#{attr}-#{k}-#{_option[0]}$/
              elements.push({"attr" => attr, "key" => k, "value" => value, "num" => i+1})
            end
          end
        end
      end
    end

    return elements
  end

  # Parse options to identify elements that should be disabled or enabled.
  def get_oc_disable_attrs(options, form)
    disable_elements = []
    enable_elements  = []
    return disable_elements, enable_elements if options.nil? || options.empty?
    
    options.each do |option|
      next if option.is_a?(Hash) # Skip if the option is a Hash
      
      form.each do |k, v|
        if option =~ /^disable-#{k}$/
          disable_elements.push({"key" => k})
        elsif option =~ /^enable-#{k}$/
          enable_elements.push({"key" => k})
        elsif ["number", "text", "email"].include?(v["widget"])
          if option =~ /^disable-#{k}-(\d+)$/
            disable_elements.push({"key" => k, "num" => $1.to_i})
          elsif option =~ /^enable-#{k}-(\d+)$/
            enable_elements.push({"key" => k, "num" => $1.to_i})
          end
        elsif ["select", "multi_select", "radio", "checkbox"].include?(v["widget"])
          v['options'].each_with_index do |_option, i|
            if option =~ /^disable-#{k}-#{_option[0]}$/
              if v["widget"] == "multi_select"
                disable_elements.push({"key" => k, "num" => i+1, "value" => _option[0]})
              else
                disable_elements.push({"key" => k, "num" => i+1})
              end
            elsif option =~ /^enable-#{k}-#{_option[0]}/
              if v["widget"] ==	"multi_select"
                enable_elements.push({"key" => k, "num" => i+1, "value" => _option[0]})
              else
                enable_elements.push({"key" => k, "num" => i+1})
              end
            end
          end
        end
      end
    end
    
    return disable_elements, enable_elements
  end

  # Return a size of the target form element based on its type.
  # For radio or checkbox widgets, the size is determined by the number of options.
  # For other widgets, it checks for a 'size' attribute.
  def get_target_size(target_key, form)
    widget = form[target_key]["widget"]
    
    if ["radio", "checkbox"].include?(widget)
      return form[target_key]["options"].size
    elsif form[target_key].key?("size")
      return form[target_key]["size"]
    else
      return "null"
    end
  end

  # Output a JavaScript code to initialize disable of widgets.
  def output_init_dw_disable_js(options, form)
    js = ""
    
    options.each do |option|
      disable_elements, enable_elements = get_oc_disable_attrs(option[2..-1], form)
      elements = disable_elements + enable_elements
      elements.each do |e|
        num  = e.key?('num') ? e['num'] : "null"
        size = get_target_size(e['key'], form)
        js  += "  ocForm.enableWidget('#{e['key']}', #{num}, '#{form[e['key']]['widget']}', #{size});\n"
        js  += "  ocForm.showWidget('#{e['key']}', '#{form[e['key']]['widget']}', #{size});\n" unless e.key?('num')
      end
    end
    
    return js
  end

  # Output a JavaScript code to enable/disable and/or show/hide widgets.
  def output_exec_dw_disable_js(key, options, form)
    js = ""
    ["disable", "enable"].each do |type|
      is_disable = type == "disable"
      conditions_by_key = Hash.new { |hash, key| hash[key] = Set.new }
      actions_by_key    = Hash.new { |hash, key| hash[key] = Set.new }

      options.each_with_index do |option, i|
        elements = is_disable ? get_oc_disable_attrs(option[2..-1], form).first : get_oc_disable_attrs(option[2..-1], form).last
        
        elements.each do |e|
          check = is_disable ? 'ocForm.isElementChecked' : '!ocForm.isElementChecked'
          _key = e.key?('num') ? e['key'] + e['num'].to_s : e['key']
          conditions_by_key[_key] << "#{check}(\"#{key}_#{i+1}\")" 
          actions_by_key[_key] << {
            num:    e.key?('num') ? e['num'] : "null",
            widget: form[e['key']]['widget'],
            value:  e.key?('value') ? e['value'] : "null",
            size:   get_target_size(e['key'], form)
          }
        end
      end
      
      join_operator = is_disable ? ' || ' : ' && '
      conditions_by_key.each do |k, conditions|
        js += "  if(#{conditions.to_a.join(join_operator)}){\n"
        actions_by_key[k].each do |action|
          if action[:num] == "null"
            js += "    ocForm.disableWidget('#{k}', #{action[:num]}, '#{action[:widget]}', \"#{action[:value]}\", #{action[:size]});\n"
            js += "    ocForm.hideWidget('#{k}', '#{action[:widget]}', #{action[:size]});\n"
          else
            js += "    ocForm.disableWidget('#{k.chomp(action[:num].to_s)}', #{action[:num]}, '#{action[:widget]}', \"#{action[:value]}\", #{action[:size]});\n"
          end
        end
        js += "  }\n"
      end
    end

    return js
  end
  
  # Parse options to identify elements that should be hide or show.
  def get_oc_hide_attrs(options, form)
    hide_elements = []
    show_elements = []
    return hide_elements, show_elements if options.nil? || options.empty?

    options.each do |option|
      next if option.is_a?(Hash)
      
      form.each do |k, v|
        next unless form[k].is_a?(Hash)
        case option
        when /^hide-#{k}$/
          hide_elements.push({"key" => k})
        when /^show-#{k}$/
          show_elements.push({"key" => k})
        end
      end
    end
    
    return hide_elements, show_elements
  end

  # Output a JavaScript code to initialize the display of widgets.
  def output_init_dw_hide_js(options, form)
    js = ""
    options.each do |option|
      hide_elements, show_elements = get_oc_hide_attrs(option[2..-1], form)
      elements = hide_elements + show_elements
      elements.each do |e|
        size = get_target_size(e['key'], form)
        js += "  ocForm.showWidget('#{e['key']}', '#{form[e['key']]['widget']}', \"#{size}\");\n"
      end
    end
    
    return js
  end

  # Output a JavaScript code to hide or show widgets.
  def output_exec_dw_hide_js(key, options, form)
    js = ""
    ["hide", "show"].each do |type|
      is_hide = type == "hide"
      conditions_by_key = Hash.new { |hash, key| hash[key] = Set.new }
      actions_by_key    = Hash.new { |hash, key| hash[key] = Set.new }
    
      options.each_with_index do |option, i|
        elements = is_hide ? get_oc_hide_attrs(option[2..-1], form).first : get_oc_hide_attrs(option[2..-1], form).last
      
        elements.each do |e|
          check = is_hide ? 'ocForm.isElementChecked' : '!ocForm.isElementChecked'
          conditions_by_key[e['key']] << "#{check}(\"#{key}_#{i+1}\")"
          actions_by_key[e['key']] << {
            widget: form[e['key']]['widget'],
            size: get_target_size(e['key'], form)
          }
        end
      end
    
      join_operator = is_hide ? ' || ' : ' && '
      conditions_by_key.each do |k, conditions|
        js += "  if(#{conditions.to_a.join(join_operator)}){\n"
        actions_by_key[k].each do |action|
          js += "    ocForm.hideWidget('#{k}', '#{action[:widget]}', \"#{action[:size]}\");\n"
        end
        js += "  }\n"
      end
    end
    
    return js
  end
  
  # Output a JavaScript code to initialize widgets with specific attributes like label, value, etc.
  def output_init_dw_set_js(options, form)
    js = ""

    options.each do |option|
      elements = get_oc_set_attrs(option[2..-1], form)

      elements.each do |e|
        widget = form[e["key"]]["widget"]
        value  = form[e['key']][e['attr']]
        
        if value.is_a?(Array) && !e['num'].nil?
          value = if e['attr'] == 'label' && value.dig(1).is_a?(Array)
                    value[1][e['num']-1]
                  else
                    value[e['num']-1]
                  end
          if e['attr'] == 'label' && form[e['key']].key?("required") && form[e['key']]["required"][e['num']-1].to_s == "true"
            value = value.nil? ? "*" : value + "*"
          end
        else
          required = if form[e['key']].key?("required")
                       e['num'].nil? ? form[e['key']]["required"].to_s == "true" : form[e['key']]["required"][e['num']-1].to_s == "true"
                     else
                       false
                     end

          if e['attr'] == 'label' && value.is_a?(Array) && value.dig(1).is_a?(Array)
            value = value[0]
            value = value.nil? ? "*" : value + "*" if required
          elsif e['attr'] == 'label' && form[e["key"]].key?("options")
            value = form[e["key"]]["options"][e['num']-1][0]
            value = value.nil? ? "*" : value + "*" if required
          end
        end

        js += "  ocForm.setInitValue('#{e['key']}', '#{e['num']}', '#{widget}', '#{e['attr']}', '#{value}', fromId);\n"
      end
    end
    
    return js
  end

  # Output a JavaScript code to initialize widgets with set, disable, and hide directives.
  def output_init_dw_js(options, form)
    return "" if options == nil
    js  = output_init_dw_set_js(options, form)
    js += output_init_dw_disable_js(options, form)
    js += output_init_dw_hide_js(options, form)
    
    return js
  end

  # Output a JavaScript code to set values.
  def output_exec_dw_set_js(key, options, form)
    js = ""
    options.each_with_index do |option, i|
      elements = get_oc_set_attrs(option[2..-1], form)
      next if elements.empty?

      js += "  if(ocForm.isElementChecked('#{key}_#{i+1}')){\n"
      
      elements.each do |e|
        widget = form[e["key"]]["widget"]
        if e['value'].is_a?(Array)
          e['value'].each do |j|
            js += "    ocForm.setValue('#{e['key']}', '#{e['num']}', '#{widget}', '#{e['attr']}', '#{j}', fromId);\n"
          end
        else
          if e["attr"] == "label" && form[e['key']].key?("required")
            if form[e['key']]["required"].is_a?(Array)
              e['value'] += "*" if form[e['key']]["required"][e['num'] - 1].to_s == "true"
            else
              e['value'] += "*" if form[e['key']]["required"].to_s == "true"
            end
          end
          js += "    ocForm.setValue('#{e['key']}', '#{e['num']}', '#{widget}', '#{e['attr']}', '#{e['value']}', fromId);\n"
        end
      end
      
      js += "  }\n"
    end
    
    return js
  end

  # Output a JavaScript code to execute widget logic based on set, disable, and hide directives.
  def output_exec_dw_js(key, options, form)
    return "" if options == nil
    js  = output_exec_dw_set_js(key, options, form)
    js += output_exec_dw_disable_js(key, options, form)
    js += output_exec_dw_hide_js(key, options, form)
    
    return js
  end

  # Output a body of webform.
  def output_body(body, header, app_name, dir_name)
    return "" unless body&.key?("form")

    @js ||= { "init_dw" => "", "exec_dw" => "", "script" => "", "once" => "", "submit" => "" }
    form = body["form"].merge({OC_SCRIPT_CONTENT => {"widget" => "textarea"}})
    obj = form.merge(header)
    html = ""
    form.each_with_index do |(key, value), index|
      next if key == OC_SCRIPT_CONTENT
      indent = add_indent_style(value)
      html  += "<div class=\"mb-3 position-relative\" style=\"#{indent}\">\n"
      
      case value['widget']
      when 'number', 'text', 'email'
        html += output_number_text_email_html(key, value)
      when 'select'
        @js["init_dw"] += output_init_dw_js(value["options"], obj)
        @js["exec_dw"] += output_exec_dw_js(key, value["options"], obj)
        html += output_select_html(key, value)
      when 'multi_select'
        @js["once"] += output_multi_select_js(key, value)
        html += output_multi_select_html(key, value)
      when 'radio'
        @js["init_dw"] += output_init_dw_js(value["options"], obj)
        @js["exec_dw"] += output_exec_dw_js(key, value["options"], obj)
        html += output_radio_html(key, value)
      when 'checkbox'
        @js["init_dw"] += output_init_dw_js(value["options"], obj)
        @js["exec_dw"] += output_exec_dw_js(key, value["options"], obj)
        @js["exec_dw"] += output_checkbox_js(key, value)
        html += output_checkbox_html(key, value)
      when 'path'
        html += output_path_html(key, value)
      end
      
      html += "</div>\n"
    end

    script_content = body["script"].is_a?(Hash) ? body.dig("script", "content") : body["script"]
    if !script_content.nil?
      script_content.split("\n").each do |line|
        @js["script"] += output_script_js(obj, line, app_name, dir_name)
      end
    end

    submit_content = body["submit"].is_a?(Hash) ? body.dig("submit", "content") : body["submit"]
    if !submit_content.nil?
      submit_content.split("\n").each do |line|
        @js["submit"] += output_script_js(obj, line, app_name, dir_name)
      end
    end

    return html
  end

  # Output a header of webform. This function is a shorthand for output_body().
  def output_header(body, header)
    return "" if header.nil? || header.empty?

    @js = {"init_dw" => "", "exec_dw" => "", "script" => "", "once" => "", "submit" => ""}
    
    html = ""
    header = header.merge({OC_SCRIPT_CONTENT => {"widget" => "textarea"}})
    obj    = header.merge(body["form"])
    header.each_with_index do |(key, value), index|
      next if key == OC_SCRIPT_CONTENT
      indent = add_indent_style(value)
      html  += "<div class=\"mb-3 position-relative\" style=\"#{indent}\">\n"

      case value['widget']
      when 'number', 'text', 'email'
        html += output_number_text_email_html(key, value)
      when 'select'
        @js["init_dw"] += output_init_dw_js(value["options"], obj)
	@js["exec_dw"] += output_exec_dw_js(key, value["options"], obj)
        html += output_select_html(key, value)
      when 'multi_select'
        @js["once"] += output_multi_select_js(key, value)
        html += output_multi_select_html(key, value)
      when 'radio'
        @js["init_dw"] += output_init_dw_js(value["options"], obj)
        @js["exec_dw"] += output_exec_dw_js(key, value["options"], obj)
        html += output_radio_html(key, value)
      when 'checkbox'
        @js["init_dw"] += output_init_dw_js(value["options"], obj)
        @js["exec_dw"] += output_exec_dw_js(key, value["options"], obj)
        @js["exec_dw"] += output_checkbox_js(key, value)
        html += output_checkbox_html(key, value)
      when 'path'
        html += output_path_html(key, value)
      end
      
      html += "</div>\n"
    end

    return html
  end
end
