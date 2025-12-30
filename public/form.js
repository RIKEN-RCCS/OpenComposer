// Adjust a textarea height based on the content.
ocForm.updateHeight = function(area) {
  area.style.height = 'auto';
  area.rows = area.value.split('\n').length;
};

// Return a valid suggestion items.
ocForm.validSuggestionItems = function(id) {
  const ulElement = document.getElementById("validSuggestions_" + id);
  return ulElement.querySelectorAll('li');
}

// Return an array of valid suggestion items.
ocForm.getValidSuggestions = function(id) {
  const ulElement = document.getElementById("validSuggestions_" + id);
  const listItems = ulElement.getElementsByTagName('li');
  return Array.from(listItems).map(li => li.textContent);
};

// Return a search input element.
ocForm.getSearchInput = function(id) {
  return document.getElementById(id);
};

// Return suggestions list element.
ocForm.getSuggestionsList = function(id) {
  return document.getElementById("suggestionsList_" + id);
};

// Return an add button element.
ocForm.getAddButton = function(id) {
  return document.getElementById("addButton_" + id);
};

// Return a selected items element.
ocForm.getSelectedItems = function(id) {
  return document.getElementById("selectedItems_" + id);
};

// Hide suggestions by clearing its content.
ocForm.hideSuggestions = function(id) {
  const suggestionsList = ocForm.getSuggestionsList(id);
  suggestionsList.innerHTML = '';
};

// Display suggestions based on the current search input.
ocForm.showSuggestions = function(id, showAll = false) {
  const searchInput = ocForm.getSearchInput(id);
  const suggestionsList = ocForm.getSuggestionsList(id);
  const validSuggestions = ocForm.getValidSuggestions(id);
  const query = searchInput.value.toLowerCase();
  suggestionsList.innerHTML = '';
  ocForm.updateAddButtonState(id, validSuggestions);

  let i = 0;
  validSuggestions.forEach((suggestion) => {
    if (showAll || suggestion.toLowerCase().includes(query)) {
      const li = document.createElement('li');
      li.classList.add('list-group-item', 'list-group-item-action', 'z-3');
      li.textContent = suggestion;

      if (Object.values(ocForm.multiSelectDisabledIndexes).includes(i++)) {
        li.style.pointerEvents = 'none';
        li.style.opacity = '0.5';
        li.style.background = "black";
        li.style.color = "white";
      }

      // Event listeners for click, mousedown, mouseover, and mouseout events.
      li.addEventListener('click', () => {
        searchInput.value = suggestion;
        suggestionsList.innerHTML = '';
        ocForm.updateAddButtonState(id, validSuggestions);
      });

      li.addEventListener('mousedown', () => {
        searchInput.value = suggestion;
        suggestionsList.innerHTML = '';
        ocForm.updateAddButtonState(id, validSuggestions);
      });

      li.addEventListener('mouseover', () => {
        ocForm.clearActiveItems(id);
        li.classList.add('active');
      });

      li.addEventListener('mouseout', () => {
        li.classList.remove('active');
      });

      suggestionsList.appendChild(li);
    }
  });
};

// Handle keyboard navigation and selection in the suggestions list.
ocForm.handleKeyDown = function(event, id) {
  const suggestionsList = ocForm.getSuggestionsList(id);
  const items = suggestionsList.getElementsByClassName('list-group-item');
  let currentIndex = -1;

  Array.from(items).some((item, index) => {
    if (item.classList.contains('active')) {
      currentIndex = index;
      return true; // escape loop
    }
  });

  if (['ArrowDown', 'ArrowUp', 'Enter'].includes(event.key)) {
    event.preventDefault();
    
    if (event.key === 'ArrowDown' && currentIndex < items.length - 1) {
      currentIndex++;
      ocForm.updateActiveItem(items, currentIndex, id);
    }
    else if (event.key === 'ArrowUp' && currentIndex > 0) {
      currentIndex--;
      ocForm.updateActiveItem(items, currentIndex, id);
    }
    else if (event.key === 'Enter') {
      const input = ocForm.getSearchInput(id);
      if (input.value !== "") {
	ocForm.addSelectedItem(id);
      }
      if (currentIndex >= 0) {
	input.value = items[currentIndex].textContent;
      }
      suggestionsList.innerHTML = '';
    }
  }
};

// Update the active item in the suggestions list.
ocForm.updateActiveItem = function(items, currentIndex, id) {
  ocForm.clearActiveItems(id);
  if (currentIndex >= 0) {
    items[currentIndex].classList.add('active');
  }
};

// Clear active items in the suggestions list.
ocForm.clearActiveItems = function(id) {
  const items = ocForm.getSuggestionsList(id).getElementsByClassName('list-group-item');
  Array.from(items).forEach(item => item.classList.remove('active'));
};

// Enable or disable an add button based on the validity of the selected suggestion.
ocForm.updateAddButtonState = function(id, validSuggestions) {
  const searchInput = ocForm.getSearchInput(id).value;
  const addButton = ocForm.getAddButton(id);

  addButton.disabled = !validSuggestions.includes(searchInput);
};

// Update hidden values which are used in cache.
ocForm.updateHiddenValues = function(id) {
  const hiddenValues = document.getElementById("hiddenValues_" + id);
  const selectedItems = ocForm.getSelectedItems(id);
  const anchors = Array.from(selectedItems.getElementsByTagName('a'));

  hiddenValues.innerHTML = "";
  anchors.forEach((anchor, i) => {
    const hiddenInput = document.createElement('input');
    hiddenInput.type = 'hidden';
    hiddenInput.name = `${id}_${i+1}`;
    hiddenInput.value = anchor.textContent;
    hiddenValues.appendChild(hiddenInput);
  });

  const lengthInput = document.createElement('input');
  lengthInput.type = 'hidden';
  lengthInput.name = `${id}_length`;
  lengthInput.value = anchors.length;
  hiddenValues.appendChild(lengthInput);
};

// Check a submission botton state
ocForm.checkSubmitState = function(id) {
  const searchInput = ocForm.getSearchInput(id);
  const submitBotton = document.getElementById("_submitButton");
  
  if (searchInput.dataset.required === "false") {
    submitBotton.disabled = false;
  }
  else{
    const selectedItems = ocForm.getSelectedItems(id);
    const anchors = Array.from(selectedItems.getElementsByTagName('a'));
    submitBotton.disabled = (anchors.length === 0);
  }
}

// Add a selected item to the display inputs.
ocForm.addSelectedItem = function(id, updateValuesFlag = true) {
  const searchInput = ocForm.getSearchInput(id);
  const selectedItems = ocForm.getSelectedItems(id);
  const validSuggestions = ocForm.getValidSuggestions(id);
  const selectedText = searchInput.value;
  const anchors = Array.from(selectedItems.getElementsByTagName('a'));

  if (selectedText && validSuggestions.includes(selectedText)) {
    const badge = document.createElement('a');
    badge.href = "#";
    badge.classList.add('badge', 'rounded-pill', 'bg-primary', 'p-2', 'text-white', 'text-decoration-none');
    badge.textContent = selectedText;
    const validSuggestionItems = ocForm.validSuggestionItems(id);
    Array.from(validSuggestionItems).some(li => {
      if (li.textContent.trim() === selectedText) {
	badge.setAttribute('data-value', li.getAttribute('data-value'));
	return true; // Escape loop
      }
    });
    
    badge.addEventListener('click', () => {
      event.preventDefault(); // Prevent the page from wrapping
      selectedItems.removeChild(badge);
      ocForm.updateHiddenValues(id);
      ocForm.checkSubmitState(id);
      ocForm.updateValues(id);
    });

    selectedItems.appendChild(badge);
    ocForm.updateHiddenValues(id);
    ocForm.checkSubmitState(id);
    searchInput.value = '';
    ocForm.updateAddButtonState(id, validSuggestions);
    
    if (updateValuesFlag) {
      ocForm.updateValues(id);
    }
  }
};

// Load files and updates the file selector interface dynamically.
ocForm.loadFiles = function(scriptName, currentPath, key, showFiles, homeDir, isFromButton) {
  const selectedPath = document.getElementById("oc-modal-data-" + key);
  if (isFromButton) {
    currentPath = selectedPath.dataset.path;
  }

  const parts = currentPath.split('/');
  let subPath = "";
  const linkedParts = parts.map(part => {
    if (part) {
      subPath += "/" + part;
      return ` <a href="#" onclick="ocForm.loadFiles('${scriptName}', '${subPath}', '${key}', ${showFiles}, '${homeDir}', false)">${part}</a> `;
    }
    else {
      return ''; // Avoid empty string for root directory
    }
  });
  
  const files_or_directory = scriptName + "/_file_or_directory";
  fetch(`${files_or_directory}?path=${encodeURIComponent(currentPath)}`)
    .then(response => response.json())
    .then(data => {
      selectedPath.dataset.path = currentPath;
      selectedPath.innerHTML = `<a href='#' onclick="ocForm.loadFiles('${scriptName}', '${homeDir}', '${key}', ${showFiles}, '${homeDir}', false)">&#x1f3e0;</a> `;
      const parentPath = currentPath.replace(/\/+$/, '').split('/').slice(0, -1).join('/') || '/';
      selectedPath.innerHTML += `<a href='#' onclick="ocForm.loadFiles('${scriptName}', '${parentPath}', '${key}', ${showFiles}, '${homeDir}', false)" style="text-decoration:none;">&#x2B06;&#xFE0F;</a> `;
      selectedPath.innerHTML += linkedParts.join('/');

      if (data.type === 'directory' && !selectedPath.dataset.path.endsWith("/")) {
        selectedPath.dataset.path += "/";
        selectedPath.innerHTML += "/";
      }
    });
  
  const checkbox = document.getElementById("oc-modal-checkbox-" + key);
  const filespath = scriptName + "/_files";
  fetch(`${filespath}?path=${encodeURIComponent(currentPath)}`)
    .then(response => response.json())
    .then(data => {
      const tbody = document.getElementById('oc-modal-tbody-' + key);
      tbody.innerHTML = '';
      if(!data.files){ return; }

      data.files.forEach(file => {
        if (file.type === 'file' && !showFiles) {
          return;
        }
        const row = document.createElement('tr');
        const typeCell = document.createElement('td');
        typeCell.innerHTML = file.type === 'file' ? '&#x1f4c4;' : '&#x1F4C1;';
        typeCell.className = 'text-center';
        
        const pathCell = document.createElement('td');
        const link = document.createElement('a');
        link.href = '#';
        link.textContent = file.name;
        link.dataset.path = file.path;
        
        link.onclick = function(e) {
          e.preventDefault();
          ocForm.loadFiles(scriptName, file.path, key, showFiles, homeDir, false);
        };

        pathCell.appendChild(link);
        row.appendChild(typeCell);
        row.appendChild(pathCell);

        if (file.name.startsWith(".") && checkbox.checked) {
          row.style.display = "none";
        }

        tbody.appendChild(row);
      });
    });
};

// Hide or show hidden files based on the checkbox state.
ocForm.hideHidden = function(key) {
  const checkbox = document.getElementById("oc-modal-checkbox-" + key);
  const tbody = document.getElementById("oc-modal-tbody-" + key);
  const rows = Array.from(tbody.getElementsByTagName("tr"));

  rows.forEach(row => {
    const cell = row.getElementsByTagName("td")[1];
    const name = cell.textContent || cell.innerText;

    if (name.startsWith(".")) {
      row.style.display = checkbox.checked ? "none" : "";
    }
  });
};

// Handle the click event on table rows to navigate between directories.
ocForm.handleRowClick = function(event, key, showFiles, scriptName, homeDir) {
  let target = event.target;
  while (target && target.nodeName !== "TR") {
    target = target.parentNode;
  }

  if (target && target.nodeName === "TR") {
    const t = target.querySelector('td:nth-child(2) a');
    ocForm.loadFiles(scriptName, t.dataset.path, key, showFiles, homeDir, false);
  }
};

// Sort the table rows based on the selected column and direction.
ocForm.sortTable = function(key, columnIndex, direction) {
  const tbody = document.getElementById("oc-modal-tbody-" + key);
  const rows = Array.from(tbody.rows);

  rows.sort((a, b) => {
    const x = a.getElementsByTagName("TD")[columnIndex].innerHTML.toLowerCase();
    const y = b.getElementsByTagName("TD")[columnIndex].innerHTML.toLowerCase();

    return direction === "asc" ? (x > y ? 1 : -1) : (x < y ? 1 : -1);
  });

  rows.forEach(row => tbody.appendChild(row));
};

// Toggle the sort direction for a column and sorts the table.
ocForm.toggleSort = function(key, columnIndex) {
  const button = document.getElementById(`oc-modal-button-${key}-${columnIndex}`);
  const direction = button.getAttribute('data-direction');

  ocForm.sortTable(key, columnIndex, direction);
  if (direction === 'asc') {
    button.innerHTML = '&#9650;';
    button.setAttribute('data-direction', 'desc');
  }
  else {
    button.innerHTML = '&#9660;';
    button.setAttribute('data-direction', 'asc');
  }
};

// Filter table rows based on the input value and hides hidden files.
ocForm.filterRows = function(key) {
  const input = document.getElementById("oc-modal-filter-" + key).value.toLowerCase();
  const tbody = document.getElementById("oc-modal-tbody-" + key);
  const rows = Array.from(tbody.getElementsByTagName("tr"));

  rows.forEach(row => {
    const cell = row.getElementsByTagName("td")[1];
    const name = cell.innerText;
    row.style.display = name.toLowerCase().includes(input) ? "" : "none";
  });

  ocForm.hideHidden(key);
};

// Check if an element is selected (e.g., a checkbox or radio button).
ocForm.isElementChecked = function(id) {
  const element = document.getElementById(id);
  if(element.disabled) return false;

  if (element.tagName === "OPTION") {
    return element.selected;
  }
  else if (element.tagName === "INPUT") {
    return element.checked;
  }
  else {
    console.error("Unknown Tag");
  }
};

// Get a parent div.
ocForm.getParentDiv = function(key, widget, size) {
  switch (widget) {
  case 'number':
  case 'text':
  case 'email':
    if (size > 1) { key = key + "_1"; }
    break;
  case 'radio':
  case 'checkbox':
    key = key + "_1";
    break;
  }

  return document.getElementById(key).closest('.mb-3');
}

// Show a widget.
ocForm.showWidget = function(key, widget, size) {
  if (key === "_script_content") {
    document.getElementById(key).style.display = 'block';
    document.getElementById("label_" + key).style.display = 'block';
    document.getElementById('_form_layout').classList.add('row-cols-lg-2');
    document.getElementById("_form_container").style.removeProperty("max-width");
  }
  else {
    const parent = ocForm.getParentDiv(key, widget, size);
    if (parent) {
      parent.style.display = 'block';
    }
  }
};

// Hide a widget.
ocForm.hideWidget = function(key, widget, size) {
  if (key === "_script_content") {
    document.getElementById(key).style.display = 'none';
    document.getElementById("label_" + key).style.display = 'none';
    document.getElementById('_form_layout').classList.remove('row-cols-lg-2');
    document.getElementById("_form_container").style.maxWidth = '960px';
  }
  else {
    const parent = ocForm.getParentDiv(key, widget, size);
    if (parent) {
      parent.style.display = 'none';
    }
  }
};

// Split the string into a key and a number.
ocForm.splitKeyAndNumber = function(str) {
  const match = str.match(/^(.+?)_(\d+)$/);
  if (match) {
    const baseKey = match[1];
    const number  = match[2];
    return { baseKey, number };
  }
  else{
    const baseKey = str;
    const number  = null;
    return { baseKey, number };
  }
}

// Return a value of a form element based on its widget type.
ocForm.getValue = function(key, widget) {
  let e = null;
  switch (widget) {
  case 'number':
  case 'text':
  case 'email':
    e = document.getElementById(key);
    if(e && !e.disabled) return e.value;
    break;
  case 'select':
    const sKey = ocForm.splitKeyAndNumber(key);
    e = document.getElementById(sKey.baseKey);
    if (e && !e.disabled && "selectedIndex" in e && e.selectedIndex !== -1) {
      const sValue = e.options[e.selectedIndex].dataset.value;
      try {
	return (sKey.number !== null) ? JSON.parse(sValue)[Number(sKey.number)-1] : sValue;
      }
      catch {
	// If JSON.parse throws an error.
	// For example, if the key is "hoge_1" but multiple items are not defined.
	return sValue;
      }
    }
    break;
  case 'multi_select':
    const mKey = ocForm.splitKeyAndNumber(key);
    const items = ocForm.getSelectedItems(mKey.baseKey);
    if(!items.disabled && !document.getElementById(mKey.baseKey).disabled){
      const aTags = items.getElementsByTagName('a');
      if (aTags) {
	return Array.from(aTags).map(a => {
	  if (ocForm.multiSelectDisabledIndexes[a.textContent] !== undefined){
	    return null;
	  }
	  else {
	    const mValue = a.getAttribute('data-value');
	    try {
	      return (mKey.number !== null) ? JSON.parse(mValue)[Number(mKey.number)-1] : mValue;
	    }
	    catch {
	      return mValue;
	    }
	  }
	}).filter(value => value !== null);
      }
    }
    break;
  case 'radio':
    const rKey = ocForm.splitKeyAndNumber(key);
    for (const e of document.getElementsByName(rKey.baseKey)) {
      if (e.checked && !e.disabled) {
	const rValue = e.dataset.value;
	try {
          return (rKey.number !== null) ? JSON.parse(rValue)[Number(rKey.number)-1] : rValue;
	}
	catch {
	  return rValue;
	}
      }
    }
    break;
  case 'checkbox':
    const cKey = ocForm.splitKeyAndNumber(key);
    const checkboxDiv = document.getElementById(cKey.baseKey + '_1').closest('div');
    const divs = checkboxDiv.parentElement.querySelectorAll('div');
    let value = [];
    divs.forEach(div => {
      const checkbox = div.querySelector('input[type="checkbox"]');
      if (checkbox !== null && checkbox.checked && !checkbox.disabled) {
        const cValue = checkbox.dataset.value;
	try {
	  if (cKey.number !== null) {
            value.push(JSON.parse(cValue)[cKey.number-1]);
	  }
	  else {
            value.push(cValue);
	  }
	}
	catch {
	  value.push(cValue);
	}
      }
    });
    return value;
  case 'path':
    if (!document.getElementById(key).disabled) {
      return document.getElementById(key).value;
    }
    break;
  }
  
  return null;
}

// Return a directory name.
ocForm.dirname = function(path) {
  if (path == null) return "";

  path = String(path);
  if (path === "") return ".";　// If path is empty, return "."

  // Remove trailing slashes (except when the entire path is just "/")
  path = path.replace(/\/+$/, "");
  
  // Find the last "/"
  const index = path.lastIndexOf("/");

  // If no "/" exists, return "."
  if (index === -1) return ".";

  // If the result is empty (e.g. "/foo" → ""), return "/"
  const dir = path.slice(0, index);
  return dir === "" ? "/" : dir;
}

// Return a base name.
ocForm.basename = function(path) {
  if (path == null) return "";

  path = String(path);

  // Remove trailing slashes (e.g. "/foo/bar///" → "/foo/bar")
  path = path.replace(/\/+$/, "");

  // Find the last "/" and return the substring after it
  const index = path.lastIndexOf("/");

  // If no "/" exists, return the whole string
  if (index === -1) return path;

  return path.slice(index + 1);
}

// Return value with zero padding
ocForm.zeroPadding = function(num, length) {
  return num === "" ? "" : String(num).padStart(length, '0');
}

// Evaluate calc(...) expression
function safeEval(expr) {
  if (!/^[0-9+\-*/().\s]+$/.test(expr)) {
    throw new Error("Invalid character is included.");
  }
  return Function(`return (${expr})`)();
}

function evalCalc(expr) {
  try {
    const parts = expr.split(",").map(s => s.trim()); // e.g. ["1 + (2 * 3)", "3", OC_ROUNDING_FLOOR]
    const valueExpr = parts[0] ?? "";
    if (valueExpr === "") return "";
    const value = safeEval(valueExpr); // 7
    const decimals = Number(parts[1]); // 3
    const rounding = parts[2];         // OC_ROUNDING_FLOOR

    // Check values
    if (!Number.isFinite(value)) throw new Error("Expression did not evaluate to a finite number.");
    if (!Number.isInteger(decimals) || decimals < 0) throw new Error("decimalPlaces must be a non-negative integer.");

    const factor = 10 ** decimals;
    const n = value * factor;  // Helper: avoid floating error a bit

    let rounded;
    if (rounding === "OC_ROUNDING_ROUND") {
      rounded = (n >= 0 ? Math.floor(n + 0.5) : Math.ceil(n - 0.5)) / factor;
    } else if (rounding === "OC_ROUNDING_FLOOR") {
      rounded = Math.floor(n) / factor;
    } else if (rounding === "OC_ROUNDING_CEIL") {
      rounded = Math.ceil(n) / factor;
    } else {
      throw new Error(`Unknown roundingMode: ${rounding}`);
    }

    return rounded.toFixed(decimals);
  } catch (e) {
    console.error(e.message);
    return "";
  }
}

// Output lines in the script contents.
ocForm.showLine = function(selectedValues, line, keys, widgets, canHide, separators) {
  // Check if line should be made visible
  for (const k in keys) {
    const value = ocForm.getValue(keys[k], widgets[k]);
    if ((value === null || value === "") && canHide[k] === false) return;
  }

  for (const k in keys) {
    let value = ocForm.getValue(keys[k], widgets[k]);
    value = typeof value === "number" ? String(value) : value;
    if (value != null && !Array.isArray(value)) { // If nothing is checked in the checkbox, value = [].
      const escapeSequences = {
	"\\n": "\n",
	"\\t": "\t",
	"\\r": "\r",
	"\\\\": "\\",
	"\\\"": "\"",
	"\\'": "'"
      };
      value = value.replace(/\\[ntr\\'"]/g, match => escapeSequences[match]);
    }

    if (value === null && canHide[k] === true) {
      value = ""
    }
    
    if (value !== null) {
      if (canHide[k] === true) {
        keys[k] = ":" + keys[k];
      }

      switch (widgets[k]) {
      case "checkbox":
      case "multi_select":
        if (separators[k] !== null){
          let tmp_value = "";
          for (let i = 0; i < value.length; i++) {
            tmp_value += value[i];
            tmp_value += (i !== value.length - 1) ? separators[k] : "";
          }
          line = (tmp_value) ? line.replace("#{" + keys[k] + "}", tmp_value) : "";
        }
        else {
          let tmp_line = "";
          for (let i = 0; i < value.length; i++) {
            tmp_line += line.replace("#{" + keys[k] + "}", value[i]);
            tmp_line += (i !== value.length - 1) ? "\n" : "";
          }
          line = tmp_line;
        }
        break;
      case "number":
      case "text":
      case "email":
      case "select":
      case "radio":
      case "path":
        line = line.replace(new RegExp(`#{${keys[k]}}`, "g"), value);
        break;
      }
    }
  }

  // After variable substitution, replace the #{zeropadding(..)} section with the calculated result.
  line = line.replace(/#\{zeropadding\(([^}]*)\)\}/g, (_, expr) => {
    const idx   = expr.lastIndexOf(",");      // "10, 3", "calc(2 * 3), 3" or "calc(2 * 3, 4), 3"
    let value   = expr.slice(0, idx).trim();  // "10", "calc(2 * 3)", "calc(2 * 3, 4)"
    const width = expr.slice(idx + 1).trim(); // "3"

    // If the first argument is calc(...), evaluate it using the same logic as #{calc(...)}
    const m = value.match(/^calc\((.*)\)$/);
    if (m) { // m[1] is the inner expression, e.g. "2 * 3"
      value = evalCalc(m[1]);
    }

    return ocForm.zeroPadding(value, width);
  });

  // After variable substitution, replace the #{calc(..)} section with the calculated result.
  line = line.replace(/#\{calc\(([^}]*)\)\}/g, (_, expr) => {
    return evalCalc(expr);
  });

  // After variable substitution, replace the #{dirname(..)} section with the calculated result.
  line = line.replace(/#\{dirname\((.*?)\)\}/g, (match, inner) => {
    return ocForm.dirname(inner);
  });

  // After variable substitution, replace the #{basename(..)} section with the calculated result.
  line = line.replace(/#\{basename\((.*?)\)\}/g, (match, inner) => {
    return ocForm.basename(inner);
  });
    
  if (line) {
    selectedValues.push(line);
  }
}

// Enable a widget.
ocForm.enableWidget = function(key, num, widget, size) {
  if (num !== null) {
    if (widget === "multi_select") {
      ocForm.multiSelectDisabledIndexes = {};
      // By assigning an empty object, all properties are removed.
      // This is fast, but may use a lot of memory since the original object is not deleted.
    }
    else {
      document.getElementById(key + "_" + num).disabled = false;
    }
  }
  else {
    switch (widget) {
    case 'number':
    case 'text':
    case 'email':
      if (size === null) {
        document.getElementById(key).disabled = false;
      }
      else {
        for (let i = 1; i <= size; i++) {
          document.getElementById(key + "_" + i).disabled = false;
        }
      }
      break;
    case 'checkbox':
    case 'radio':
      for (let i = 1; i <= size; i++) {
        document.getElementById(key + "_" + i).disabled = false;
      }
      break;
    case 'select':
    case 'multi_select':
    case 'path':
      document.getElementById(key).disabled = false;
      break;
    }
  }
};

// Disable a widget.
ocForm.disableWidget = function(key, num, widget, value, size) {
  if (num !== null) {
    if (widget === "multi_select") {
      ocForm.multiSelectDisabledIndexes[value] = num - 1;
    }
    else {
      document.getElementById(key + "_" + num).disabled = true;
      
      if (widget === 'select' && document.getElementById(key).selectedIndex === num - 1) {
	const selectBox = document.getElementById(key);

	// Find the next valid option
        const nextValidOption = Array.from(selectBox.options).find(option => !option.disabled)
	if (nextValidOption) {
	  selectBox.value = nextValidOption.value;
	}
	else {
	  selectBox.selectedIndex = -1;
	}
      }
      else if (widget === 'radio' && document.getElementsByName(key)[num - 1].checked) {
        document.getElementsByName(key)[num - 1].checked = false;
      }
    }
  }
  else {
    switch (widget) {
    case 'number':
    case 'text':
    case 'email':
      if (size === null) {
        document.getElementById(key).disabled = true;
      }
      else {
        for (let i = 1; i <= size; i++) {
          document.getElementById(key + "_" + i).disabled = true;
        }
      }
      break;
    case 'checkbox':
    case 'radio':
      for (let i = 1; i <= size; i++) {
        document.getElementById(key + "_" + i).disabled = true;
      }
      break;
    case 'select':
    case 'multi_select':
    case 'path':
      document.getElementById(key).disabled = true;
      break;
    }
  }
};

// Set a form element's attributes for initialization.
ocForm.setInitValue = function(key, num, widget, attr, value, fromId) {
  const id = num ? key + "_" + num : key;
  if ((attr === "min" || attr === "max" || attr === "step") && widget === "number") {
    document.getElementById(id).setAttribute(attr, value);
  }
  else if (attr === "label" || attr == "help") {
    const text = document.getElementById(attr + "_" + id);
    if (text !== null) {
      text.innerHTML = value;
      text.style.display = value !== "" ? "block" : "none";
    }
  }
  else if (attr === "required") {
    const label = document.getElementById("label_" + id);
    if (label !== null) {
      label.textContent = label.getAttribute('data-label');
      label.style.display = label.textContent !== "" ? "block" : "none";
      const required = label.getAttribute('data-required');
      let input;
      switch (widget) {
      case "radio":
	input = document.getElementById(id + "_1");
	break;
      case "checkbox":
	input = num == "" ? document.getElementById("label_" + id) : document.getElementById(id);
	break;
      default:
	input = document.getElementById(id);
      }

      if (required !== null && input !== null) {
	switch (widget) {
	case "checkbox":
	  if (num === "") {
	    input.setAttribute("data-required", value === "true");
	    ocForm.validateCheckboxForSubmit(id);
	  }
	  else {
	    if (value === "true") {
	      input.setAttribute('required', '');
	    }
	    else {
	      input.removeAttribute('required');
	    }
	  }
	  break;
	case "multi_select":
	  const submitBotton = document.getElementById("_submitButton");
	  if (value === "true") {
	    const selectedItems = ocForm.getSelectedItems(id);
	    const anchors = Array.from(selectedItems.getElementsByTagName('a'));
	    submitBotton.disabled = anchors.length === 0;
	  }
	  else {
	    const searchInput = ocForm.getSearchInput(id);
	    submitBotton.disabled = false;
	  }
	  break;
	default:
	  if (value === "true") {
	    input.setAttribute('required', '');
	  }
	  else {
	    input.removeAttribute('required');
	  }
	}
      }
    }
  }
  else if (attr === "value") {
    switch(widget){
    case 'number':
    case 'text':
    case 'email':
      if (id !== fromId) {
        document.getElementById(id).value = value;
      }
      break;
    case 'select':
      if (key !== fromId) {
        const selectBox = document.getElementById(key);
        const options = Array.from(selectBox.querySelectorAll('option'));

        for (let i = 0; i < options.length; i++) {
          document.getElementById(key + "_" + (i+1)).disabled = false;
        }
      }
      break;
    case 'multi_select':
    case 'checkbox':
      break;
    case 'radio':
      const parentDiv = document.getElementById(key + '_1').closest('div');
      const divs = parentDiv.parentElement.querySelectorAll('div');

      divs.forEach(div => {
	const input = div.querySelector(`input[type="${widget}"]`);
	if (input !== null) {
  	  input.disabled = false;
	}
      });
      break;
    case 'path':
      if(key !== fromId){
        document.getElementById("oc-modal-data-" + key).dataset.path = value;
        document.getElementById(key).value = value;
      }
      break;
    } // end widget
  } // end if (attr === "value")
};

// Set a form element's attributes.
ocForm.setValue = function(key, num, widget, attr, value, fromId) {
  const id = num ? key + "_" + num : key;
  if ((attr === "min" || attr === "max" || attr === "step") && widget === "number") {
    ocForm.setInitValue(key, num, widget, attr, value, fromId);
  }
  else if (attr === "label" || attr === "help"){
    ocForm.setInitValue(key, num, widget, attr, value, fromId);
  }
  else if (attr === "required") {
    const label = document.getElementById("label_" + id);

    if (label !== null) {
      label.textContent = label.textContent.trim();
      label.style.display = label.textContent !== "" ? "block" : "none";
      const required = label.getAttribute('data-required');
      let input;
      switch (widget) {
      case "radio":
	input = document.getElementById(id + "_1");
	break;
      case "checkbox":
	input = num == "" ? document.getElementById("label_" + id) : document.getElementById(id);
	break;
      default:
	input = document.getElementById(id);
      }

      if (required !== null && input !== null) {
	switch (widget) {
	case "checkbox":
	  if (num === "") {
	    input.setAttribute("data-required", value === "true");
	    ocForm.validateCheckboxForSubmit(id);
	  }
	  else {
	    if (value === "true") {
	      input.setAttribute('required', '');
	    }
	    else {
	      input.removeAttribute('required');
	    }
	  }
	  break;
	case "multi_select":
	  const submitBotton = document.getElementById("_submitButton");
          if (value === "true") {
            const selectedItems = ocForm.getSelectedItems(id);
            const anchors = Array.from(selectedItems.getElementsByTagName('a'));
            submitBotton.disabled = anchors.length === 0;
          }
          else {
            const searchInput = ocForm.getSearchInput(id);
            submitBotton.disabled = false;
          }
	  break;
	default:
	  if (value === "true") {
	    input.setAttribute('required', '');
	  }
	  else {
	    input.removeAttribute('required');
	  }
	}
      }
      
      if (required !== null) {
	if (value === "true" && required !== "true") {
	  label.textContent = label.textContent.trim() + "*";
	  label.style.display = "block";
	}
	else if (value === "false" && required === "true") {
	  label.textContent = label.textContent.trim().slice(0, -1); // Delete only the last character (*).
	  label.style.display = label.textContent !== "" ? "block" : "none";
	}
      }
    }
  }
  else if (attr === "value") {
    switch(widget){
    case 'number':
    case 'text':
    case 'email':
    case 'path':
      ocForm.setInitValue(key, num, widget, attr, value, fromId);
      break;
    case 'select':
      if (key !== fromId) {
        const selectBox = document.getElementById(key);
        const options = Array.from(selectBox.querySelectorAll('option'));

        for (let i = 0; i < options.length; i++) {
          if (options[i].textContent === value) {
            document.getElementById(key).selectedIndex = i;
          }
        }
      }
      break;
    case 'multi_select':
      if (key !== fromId) {
        ocForm.getSearchInput(key).value = value;
        ocForm.addSelectedItem(key, false);
      }
      break;
    case 'radio':
    case 'checkbox':
      if (typeof fromId === 'undefined' || key !== fromId.replace(/_\d+$/, "")) { // hoge_2 -> hoge
	const parentDiv = document.getElementById(key + '_1').closest('div');
	const divs = parentDiv.parentElement.querySelectorAll('div');
	divs.forEach(div => {
	  const input = div.querySelector(`input[type="${widget}"]`);
	  if (input !== null) {
            const label = div.querySelector(`label[for="${input.id}"]`);
            if (label.textContent === value) {
              input.checked = true;
            }
	  }
	});
      }
      break;
    } // end widget
  } // end if (attr === "value")
};

// Update the selected path in the file input.
ocForm.updatePath = function(key) {
  document.getElementById(key).value = document.getElementById("oc-modal-data-" + key).dataset.path;
  ocForm.updateValues(key);
};

// If a checkbox widget has `required: true` attribute and none are checked,
// disable the submit button. If any are checked, enable the submit button.
ocForm.validateCheckboxForSubmit = function(key) {
  const checkboxLabel = document.getElementById("label_" + key);
  if(checkboxLabel.getAttribute("data-required") === "false") {
    document.getElementById("_submitButton").disabled = false;
    return;
  }
  else{
    const checkboxDiv = document.getElementById(key + "_1").closest('div');
    const divs = checkboxDiv.parentElement.querySelectorAll('div');
    const isChecked = Array.from(divs).some(div => {
      const checkbox = div.querySelector('input[type="checkbox"]');
      return checkbox !== null && checkbox.checked && !checkbox.disabled;
    });
    document.getElementById("_submitButton").disabled = !isChecked;
  }
};

// Show "Submitting..." on the button and disable it to prevent double submission.
// The form is submitted normally and the button resets after page reload. 
ocForm.submitEffect = function(action) {
  const btn = document.getElementById('_submitButton');
  btn.disabled = true;
  if (action === "submit") {
    btn.value = 'Submitting...';
  }
  else if (action === "save") {
    btn.value = 'Saving...';
  }
  // Note that confirm is not needed.
    
  btn.classList.remove('btn-primary');
  btn.classList.add('btn-warning');

  return true;
};

