/*
 * Lesson editor for the Django admin: formatting toolbar + live Markdown preview.
 * The preview HTML is passed through a whitelist sanitizer before display.
 */
(function () {
  "use strict";

  var ALLOWED_TAGS = {
    P: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, STRONG: 1, EM: 1, DEL: 1, CODE: 1, PRE: 1,
    BLOCKQUOTE: 1, UL: 1, OL: 1, LI: 1, A: 1, IMG: 1, TABLE: 1, THEAD: 1, TBODY: 1, TR: 1,
    TH: 1, TD: 1, HR: 1, BR: 1
  };
  var ALLOWED_ATTRS = {
    A: ["href", "title"], IMG: ["src", "alt", "title"], TH: ["align"], TD: ["align"],
    OL: ["start"], CODE: ["class"]
  };

  function isSafeUrl(url, forImage) {
    url = (url || "").trim();
    if (/^https?:\/\//i.test(url)) return true;
    if (url.charAt(0) === "/" && url.charAt(1) !== "/" && url.charAt(1) !== "\\") return true;
    return !forImage && /^mailto:/i.test(url);
  }

  function sanitize(html) {
    var doc = new DOMParser().parseFromString("<div>" + html + "</div>", "text/html");
    var root = doc.body.firstChild;
    (function clean(node) {
      Array.prototype.slice.call(node.childNodes).forEach(function (child) {
        if (child.nodeType === 3) return; // text
        if (child.nodeType !== 1) { node.removeChild(child); return; }
        if (!ALLOWED_TAGS[child.tagName]) {
          node.replaceChild(doc.createTextNode(child.textContent || ""), child);
          return;
        }
        var allowed = ALLOWED_ATTRS[child.tagName] || [];
        Array.prototype.slice.call(child.attributes).forEach(function (attr) {
          var name = attr.name.toLowerCase();
          if (allowed.indexOf(name) === -1) { child.removeAttribute(attr.name); return; }
          if ((name === "href" || name === "src") && !isSafeUrl(attr.value, name === "src")) {
            child.removeAttribute(attr.name);
          }
        });
        if (child.tagName === "A") {
          child.setAttribute("target", "_blank");
          child.setAttribute("rel", "noopener noreferrer");
        }
        clean(child);
      });
    })(root);
    return root.innerHTML;
  }

  function replaceSelection(textarea, before, after, placeholder) {
    var start = textarea.selectionStart;
    var end = textarea.selectionEnd;
    var value = textarea.value;
    var selected = value.slice(start, end) || placeholder;
    textarea.value = value.slice(0, start) + before + selected + after + value.slice(end);
    textarea.focus();
    textarea.selectionStart = start + before.length;
    textarea.selectionEnd = start + before.length + selected.length;
    textarea.dispatchEvent(new Event("input"));
  }

  function prefixLines(textarea, prefix, numbered) {
    var start = textarea.value.lastIndexOf("\n", textarea.selectionStart - 1) + 1;
    var end = textarea.selectionEnd;
    var block = textarea.value.slice(start, end) || "List item";
    var n = 0;
    var updated = block.split("\n").map(function (line) {
      n += 1;
      return (numbered ? n + ". " : prefix) + line;
    }).join("\n");
    textarea.value = textarea.value.slice(0, start) + updated + textarea.value.slice(end);
    textarea.focus();
    textarea.selectionStart = start;
    textarea.selectionEnd = start + updated.length;
    textarea.dispatchEvent(new Event("input"));
  }

  var BUTTONS = [
    { label: "B", title: "Bold", run: function (t) { replaceSelection(t, "**", "**", "bold text"); } },
    { label: "I", title: "Italic", run: function (t) { replaceSelection(t, "_", "_", "italic text"); } },
    { label: "H2", title: "Heading", run: function (t) { prefixLines(t, "## ", false); } },
    { label: "H3", title: "Sub-heading", run: function (t) { prefixLines(t, "### ", false); } },
    { label: "• List", title: "Bullet list", run: function (t) { prefixLines(t, "- ", false); } },
    { label: "1. List", title: "Numbered list", run: function (t) { prefixLines(t, "", true); } },
    { label: "❝ Quote", title: "Quote / tip box", run: function (t) { prefixLines(t, "> ", false); } },
    { label: "Code", title: "Inline code", run: function (t) { replaceSelection(t, "`", "`", "code"); } },
    { label: "Code block", title: "Code block", run: function (t) { replaceSelection(t, "\n```\n", "\n```\n", "your code here"); } },
    { label: "Link", title: "Link", run: function (t) { replaceSelection(t, "[", "](https://)", "link text"); } },
    { label: "Table", title: "Table", run: function (t) {
      replaceSelection(t, "\n| Column 1 | Column 2 |\n| --- | --- |\n| ", " | Value |\n", "Value");
    } }
  ];

  function setup(textarea) {
    var wrapper = document.createElement("div");
    wrapper.className = "li-md";
    var toolbar = document.createElement("div");
    toolbar.className = "li-md-toolbar";
    var panes = document.createElement("div");
    panes.className = "li-md-panes";
    var previewBox = document.createElement("div");
    previewBox.className = "li-md-preview-box";
    var previewLabel = document.createElement("div");
    previewLabel.className = "li-md-label";
    previewLabel.textContent = "Preview";
    var preview = document.createElement("div");
    preview.className = "li-md-preview";

    textarea.parentNode.insertBefore(wrapper, textarea);
    wrapper.appendChild(toolbar);
    wrapper.appendChild(panes);
    panes.appendChild(textarea);
    previewBox.appendChild(previewLabel);
    previewBox.appendChild(preview);
    panes.appendChild(previewBox);

    BUTTONS.forEach(function (b) {
      var button = document.createElement("button");
      button.type = "button";
      button.textContent = b.label;
      button.title = b.title;
      button.addEventListener("click", function () { b.run(textarea); });
      toolbar.appendChild(button);
    });

    var timer = null;
    function render() {
      var markdown = textarea.value || "";
      var html = "";
      if (window.marked && typeof window.marked.parse === "function") {
        html = window.marked.parse(markdown, { async: false, gfm: true, breaks: false });
      }
      var safe = sanitize(html);
      preview.innerHTML = safe || '<p class="li-md-empty">Start typing to see the preview.</p>';
    }
    textarea.addEventListener("input", function () {
      clearTimeout(timer);
      timer = setTimeout(render, 150);
    });
    render();
  }

  document.addEventListener("DOMContentLoaded", function () {
    Array.prototype.forEach.call(document.querySelectorAll("textarea.li-markdown"), setup);
  });
})();
