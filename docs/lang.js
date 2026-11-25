// Spanish is the default; English is one click away and remembered on this device.
// Old links ending in #en still open the English version.
// A page can pick another default with data-default-lang (the code signing policy stays English first for reviewers).
(function () {
  var root = document.documentElement;
  function stored() { try { return localStorage.getItem("voltadock-lang"); } catch (e) { return null; } }
  function remember(l) { try { localStorage.setItem("voltadock-lang", l); } catch (e) {} }
  var q = new URLSearchParams(location.search).get("lang");
  var hash = location.hash.replace("#", "");
  var lang = q === "en" || q === "es" ? q : hash === "en" || hash === "es" ? hash : stored() || root.getAttribute("data-default-lang") || "es";
  function apply(l) {
    root.setAttribute("data-lang", l);
    root.setAttribute("lang", l);
    var t = root.getAttribute("data-title-" + l);
    if (t) document.title = t;
    var b = document.querySelectorAll(".lang button");
    for (var i = 0; i < b.length; i++) b[i].setAttribute("aria-pressed", String(b[i].getAttribute("data-set") === l));
  }
  apply(lang);
  document.addEventListener("DOMContentLoaded", function () {
    apply(root.getAttribute("data-lang"));
    document.addEventListener("click", function (e) {
      var t = e.target.closest && e.target.closest(".lang button");
      if (!t) return;
      var l = t.getAttribute("data-set");
      remember(l); apply(l);
    });
  });
})();
