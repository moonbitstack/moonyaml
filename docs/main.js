/* The site's two behaviours: the theme, and the copy buttons.
 *
 * The theme is already on <html> by the time this runs — the head does that, so
 * the first paint is the right colour. All that is left here is to flip it, keep
 * the button in step, and remember the choice.
 */
(function () {
  "use strict";

  var root = document.documentElement;
  var dark = "dark";
  var light = "light";

  function stored() {
    try {
      return localStorage.getItem("theme");
    } catch (e) {
      return null; // a browser that refuses storage still gets the toggle
    }
  }

  function remember(theme) {
    try {
      localStorage.setItem("theme", theme);
    } catch (e) {
      /* the choice lasts the page, which is better than not having one */
    }
  }

  function other(theme) {
    return theme === dark ? light : dark;
  }

  function apply(theme) {
    root.setAttribute("data-theme", theme);
    var button = document.getElementById("theme");
    if (!button) return;
    var next = other(theme);
    button.textContent = next;
    button.setAttribute("title", "Switch to the " + next + " theme");
    button.setAttribute("aria-label", "Switch to the " + next + " theme");
  }

  // The head has already decided; trust it rather than deciding again, so the
  // page and this file can never disagree about which theme is on.
  var theme = root.getAttribute("data-theme");
  if (theme !== dark && theme !== light) {
    theme = stored();
    if (theme !== dark && theme !== light) {
      theme = window.matchMedia("(prefers-color-scheme: dark)").matches ? dark : light;
    }
  }
  apply(theme);

  var toggle = document.getElementById("theme");
  if (toggle) {
    toggle.addEventListener("click", function () {
      theme = other(theme);
      remember(theme);
      apply(theme);
    });
  }

  /* -- copy ---------------------------------------------------------------
   *
   * A figure carries a code block and a button in its corner. Copying takes the
   * text of the block, not its markup, so what lands on the clipboard is what
   * the example actually says.
   */

  function text_of(button) {
    var figure = button.closest(".figure") || button.parentNode;
    var pre = figure ? figure.querySelector("pre") : null;
    return pre ? pre.innerText.replace(/\n+$/, "") + "\n" : "";
  }

  function fallback(text, done) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.top = "-1000px";
    document.body.appendChild(area);
    area.select();
    try {
      document.execCommand("copy");
    } catch (e) {
      /* nothing else to try */
    }
    document.body.removeChild(area);
    done();
  }

  function flash(button) {
    var was = button.textContent;
    button.textContent = "copied";
    button.classList.add("done");
    window.setTimeout(function () {
      button.textContent = was;
      button.classList.remove("done");
    }, 1200);
  }

  var buttons = document.querySelectorAll("button.copy");
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].addEventListener("click", function () {
      var button = this;
      var text = text_of(button);
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(
          function () {
            flash(button);
          },
          function () {
            fallback(text, function () {
              flash(button);
            });
          }
        );
      } else {
        fallback(text, function () {
          flash(button);
        });
      }
    });
  }
})();
