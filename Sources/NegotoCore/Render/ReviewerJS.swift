import Foundation

extension CardPage {
    /// Runtime support injected into every card: Anki's image-occlusion renderer API
    /// (`anki.imageOcclusion.setup()`), responsive redraws, and helpers used by the native side.
    static let reviewerJS = #"""
    (function () {
      window.anki = window.anki || {};
      var ioState = { masksVisible: true, setupDone: false };

      function cssVar(el, name, fallback) {
        var v = getComputedStyle(el).getPropertyValue(name);
        return v && v.trim() ? v.trim() : fallback;
      }
      function parseBorder(v) {
        var m = /([\d.]+)px\s+(\S+)/.exec(v || "");
        return m ? { width: parseFloat(m[1]), color: m[2] } : { width: 1, color: "#212121" };
      }
      function num(v) { var n = parseFloat(v); return isNaN(n) ? 0 : n; }

      function drawShapes() {
        var canvas = document.getElementById("image-occlusion-canvas");
        var container = document.getElementById("image-occlusion-container");
        if (!canvas || !container) return;
        var img = container.querySelector("img");
        if (!img) return;
        if (!img.complete || !img.naturalWidth) { img.addEventListener("load", drawShapes, { once: true }); return; }
        var w = img.clientWidth, h = img.clientHeight;
        var dpr = window.devicePixelRatio || 1;
        canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
        canvas.style.width = w + "px"; canvas.style.height = h + "px";
        var ctx = canvas.getContext("2d");
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, w, h);
        if (!ioState.masksVisible) return;

        var colors = {
          active: cssVar(canvas, "--active-shape-color", "#ff8e8e"),
          inactive: cssVar(canvas, "--inactive-shape-color", "#ffeba2"),
          highlight: cssVar(canvas, "--highlight-shape-color", "rgba(255,142,142,0)"),
          activeBorder: parseBorder(cssVar(canvas, "--active-shape-border", "1px #212121")),
          inactiveBorder: parseBorder(cssVar(canvas, "--inactive-shape-border", "1px #212121")),
          highlightBorder: parseBorder(cssVar(canvas, "--highlight-shape-border", "1px #ff8e8e"))
        };
        // Coordinates are normally fractions of the image size; very old notes used pixels.
        var nw = img.naturalWidth, nh = img.naturalHeight;
        function sx(v) { v = num(v); return v <= 1.0001 ? v * w : v * (w / nw); }
        function sy(v) { v = num(v); return v <= 1.0001 ? v * h : v * (h / nh); }

        var shapes = document.querySelectorAll("#qa [data-shape]");
        var texts = [];
        for (var i = 0; i < shapes.length; i++) {
          var el = shapes[i], d = el.dataset, cls = el.className;
          var fill = null, border = null;
          if (d.shape === "text") { texts.push(el); continue; }
          if (/\bcloze-inactive\b/.test(cls)) {
            if (d.occludeinactive === "1" || d.occludeInactive === "1") { fill = colors.inactive; border = colors.inactiveBorder; }
            else continue;
          } else if (/\bcloze-highlight\b/.test(cls)) {
            fill = colors.highlight; border = colors.highlightBorder;
          } else if (/\bcloze\b/.test(cls)) {
            fill = colors.active; border = colors.activeBorder;
          } else continue;
          ctx.beginPath();
          if (d.shape === "rect") {
            ctx.rect(sx(d.left), sy(d.top), sx(d.width), sy(d.height));
          } else if (d.shape === "ellipse") {
            var rx = sx(d.rx), ry = sy(d.ry);
            ctx.ellipse(sx(d.left) + rx, sy(d.top) + ry, Math.max(rx, 0.5), Math.max(ry, 0.5), 0, 0, Math.PI * 2);
          } else if (d.shape === "polygon") {
            var pts = (d.points || "").trim().split(/\s+/);
            for (var p = 0; p < pts.length; p++) {
              var xy = pts[p].split(",");
              if (p === 0) ctx.moveTo(sx(xy[0]), sy(xy[1])); else ctx.lineTo(sx(xy[0]), sy(xy[1]));
            }
            ctx.closePath();
          }
          ctx.fillStyle = fill; ctx.fill();
          if (border && border.width > 0) { ctx.lineWidth = border.width; ctx.strokeStyle = border.color; ctx.stroke(); }
        }
        for (var t = 0; t < texts.length; t++) {
          var td = texts[t].dataset;
          var scale = num(td.scale) || 1;
          var size = (num(td.fs) ? sy(td.fs) : 0.04 * h) * scale;
          ctx.font = Math.max(8, size) + "px sans-serif";
          ctx.textBaseline = "top";
          var lines = String(td.text || "").split("\n");
          for (var l = 0; l < lines.length; l++) {
            var x = sx(td.left), y = sy(td.top) + l * size * 1.2;
            var m = ctx.measureText(lines[l]);
            ctx.fillStyle = "rgba(255,255,255,0.8)";
            ctx.fillRect(x - 2, y - 2, m.width + 4, size * 1.2 + 2);
            ctx.fillStyle = "#000"; ctx.fillText(lines[l], x, y);
          }
        }
      }

      window.anki.imageOcclusion = {
        setup: function () {
          ioState.setupDone = true;
          drawShapes();
          var toggle = document.getElementById("toggle");
          if (toggle && !toggle.dataset.negoto) {
            toggle.dataset.negoto = "1";
            toggle.addEventListener("click", function () { ioState.masksVisible = !ioState.masksVisible; drawShapes(); });
          }
        },
        drawShapes: drawShapes
      };
      window.addEventListener("resize", function () { if (ioState.setupDone) drawShapes(); });

      window.negotoTypedAnswer = function () {
        var el = document.getElementById("typeans");
        return el && el.tagName === "INPUT" ? el.value : "";
      };
      window.negotoAfterRender = function () {
        var input = document.querySelector("input#typeans");
        if (input) { setTimeout(function () { try { input.focus(); } catch (e) {} }, 50); }
        if (document.body.dataset.side === "answer") {
          var a = document.getElementById("answer");
          if (a && a.getBoundingClientRect().top > window.innerHeight * 0.6) { a.scrollIntoView({ block: "start" }); }
        }
      };
    })();
    """#
}
