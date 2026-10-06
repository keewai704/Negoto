import Foundation

/// Builds the final HTML page shown in the web view for one side of a card.
public enum CardPage {
    public enum Side: String, Sendable { case question, answer }

    public struct Options: Sendable {
        public var nightMode: Bool
        public var forceDarkCards: Bool
        public var isPad: Bool
        /// Absolute file URL (ending in "/") of the folder containing bundled scripts (mathjax/).
        public var supportBaseURL: String
        public var autoplayVideo: Bool

        public init(nightMode: Bool = false, forceDarkCards: Bool = true, isPad: Bool = false,
                    supportBaseURL: String = "", autoplayVideo: Bool = false) {
            self.nightMode = nightMode
            self.forceDarkCards = forceDarkCards
            self.isPad = isPad
            self.supportBaseURL = supportBaseURL
            self.autoplayVideo = autoplayVideo
        }
    }

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "ogv", "mpg", "mpeg", "avi", "mkv", "3gp"]

    public static func isVideo(_ filename: String) -> Bool {
        videoExtensions.contains((filename as NSString).pathExtension.lowercased())
    }

    private static let playRegex = try! NSRegularExpression(pattern: "\\[anki:play:([qa]):(\\d+)\\]")

    static let playIcon = """
    <svg class="playImage" viewBox="0 0 64 64" version="1.1"><circle cx="32" cy="32" r="29"/>\
    <path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z"/></svg>
    """

    /// Inner HTML for the card side, with play buttons, type-answer box/comparison and media links resolved.
    public static func body(for card: RenderedCard, side: Side, typedAnswer: String?, resolver: MediaResolver?,
                            autoplayVideo: Bool = false) -> String {
        var html = side == .question ? card.question : card.answer

        // Type answer
        if let spec = TypeAnswer.spec(in: html) {
            if side == .question {
                let input = """
                <center><input type="text" id="typeans" autocomplete="off" autocorrect="off" autocapitalize="off" \
                spellcheck="false" enterkeyhint="done" onkeydown="if(event.key==='Enter'){event.preventDefault();negotoMessage({type:'enter'});}"></center>
                """
                html = TypeAnswer.replaceMarkers(in: html, with: input)
            } else {
                let expected = TypeAnswer.expectedAnswer(spec: spec, fields: card.fields, cardOrd: card.cardOrd)
                let cmp = TypeAnswer.comparison(typed: typedAnswer ?? "", expected: expected, ignoreCombining: spec.ignoreCombining)
                html = TypeAnswer.replaceMarkers(in: html, with: cmp)
            }
        }

        // Play buttons / inline video
        html = HTMLText.replace(playRegex, in: html) { g in
            let sideKey = g[1] ?? "q"
            let idx = Int(g[2] ?? "0") ?? 0
            let tags = sideKey == "q" ? card.questionAV : card.answerAV
            if idx < tags.count, case .sound(let file) = tags[idx], isVideo(file) {
                let src = resolver?.resolve(file).map(MediaResolver.encode) ?? MediaResolver.encode(file)
                let autoplay = autoplayVideo && sideKey == (side == .question ? "q" : "a") ? " autoplay" : ""
                return "<video class=\"negoto-video\" src=\"\(src)\" controls playsinline preload=\"metadata\"\(autoplay)></video>"
            }
            return "<a class=\"replay-button soundLink\" href=\"#\" onclick=\"negotoMessage({type:'play',side:'\(sideKey)',index:\(idx)});return false;\" draggable=\"false\">\(playIcon)</a>"
        }

        if let resolver { html = resolver.rewriteReferences(in: html) }
        return html
    }

    public static func document(card: RenderedCard, side: Side, typedAnswer: String?, resolver: MediaResolver?,
                                options: Options) -> String {
        let inner = body(for: card, side: side, typedAnswer: typedAnswer, resolver: resolver, autoplayVideo: options.autoplayVideo)
        var css = card.css
        if let resolver { css = resolver.rewriteCSS(css) }
        var bodyClasses = ["card", "card\(card.cardOrd + 1)", "mobile", "ios", options.isPad ? "ipad" : "iphone"]
        if options.nightMode { bodyClasses += ["nightMode", "night_mode"] }
        let base = options.supportBaseURL
        let darkCardCSS = options.nightMode && options.forceDarkCards ? forcedDarkCSS : ""
        return """
        <!doctype html>
        <html class="\(options.nightMode ? "night-mode" : "")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>\(baseCSS)</style>
        <style>\(darkCardCSS)</style>
        <style>\(css)</style>
        <script>\(preludeJS)</script>
        <script>\(reviewerJS)</script>
        <script>window.MathJax = \(mathJaxConfig);</script>
        <script id="MathJax-script" async src="\(base)mathjax/tex-svg-full.js"></script>
        </head>
        <body class="\(bodyClasses.joined(separator: " "))" data-side="\(side.rawValue)">
        <div id="qa">\(inner)</div>
        <script>if (window.negotoAfterRender) { negotoAfterRender(); }</script>
        </body>
        </html>
        """
    }

    static let mathJaxConfig = """
    {
      tex: { inlineMath: [["\\\\(", "\\\\)"]], displayMath: [["\\\\[", "\\\\]"]], processEscapes: false },
      svg: { fontCache: "global" },
      startup: { typeset: true },
      options: { ignoreHtmlClass: "tex2jax_ignore", processHtmlClass: "tex2jax_process" }
    }
    """

    static let preludeJS = """
    function negotoMessage(m){try{window.webkit.messageHandlers.negoto.postMessage(m);}catch(e){}}
    window.pycmd = function(cmd){ negotoMessage({type:'pycmd', cmd: String(cmd)}); };
    window.ankiPlatform = 'ios';
    window.onerror = function(msg, src, line){ negotoMessage({type:'log', message: String(msg) + ' @' + line}); };
    """

    static let baseCSS = """
    html { -webkit-text-size-adjust: 100%; }
    body { margin: 20px; overflow-wrap: break-word; background-color: #ffffff; color: #000000;
           padding-bottom: env(safe-area-inset-bottom); }
    body.nightMode { background-color: #1c1c1e; color: #f2f2f7; }
    img { max-width: 100%; max-height: 95vh; height: auto; }
    video.negoto-video { max-width: 100%; max-height: 60vh; display: block; margin: 8px auto; }
    #typeans { width: 100%; box-sizing: border-box; font-size: 1em; padding: 6px 8px; border-radius: 8px;
               border: 1px solid #8e8e93; font-family: inherit; }
    input#typeans { background: inherit; color: inherit; }
    code#typeans { display: inline-block; font-family: ui-monospace, Menlo, monospace; white-space: pre-wrap;
                   width: auto; border: none; }
    .typeGood { background-color: #afa; color: black; }
    .typeBad { background-color: #faa; color: black; }
    .typeMissed { background-color: #ccc; color: black; }
    .replay-button { display: inline-block; vertical-align: middle; margin: 2px; text-decoration: none; }
    .replay-button svg { width: 40px; height: 40px; }
    .replay-button svg circle { fill: #ffffff; stroke: #414141; stroke-width: 2px; }
    .replay-button svg path { fill: #414141; }
    .nightMode .replay-button svg circle { fill: #363636; stroke: #cccccc; }
    .nightMode .replay-button svg path { fill: #cccccc; }
    .latex-fallback { display: inline-block; }
    img.latex { vertical-align: middle; }
    .nightMode img.latex { filter: invert(1) hue-rotate(180deg); }
    #image-occlusion-container { position: relative; display: inline-block; max-width: 100%; }
    #image-occlusion-container img { display: block; max-width: 100%; max-height: none; }
    #image-occlusion-canvas { position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; }
    .negoto-template-error { color: #d70015; font-size: 0.8em; }
    """

    /// Applied in dark mode so that cards whose CSS hard-codes `.card { color: black; background: white }`
    /// still follow the system appearance. Authors' own `.nightMode` rules come later and win.
    static let forcedDarkCSS = """
    .card.nightMode { background-color: #1c1c1e; color: #f2f2f7; }
    """
}
