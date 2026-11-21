(async function() {
    console.log("Rozpoczynam zbieranie filmow...");

    function scrollDown() {
        window.scrollBy(0, 5000);
        if (document.scrollingElement) {
            document.scrollingElement.scrollTop = document.scrollingElement.scrollHeight;
        }
    }

    var lastCount = 0;
    var noChange = 0;

    while (noChange < 4) {
        scrollDown();
        await new Promise(function(resolve) { setTimeout(resolve, 1500); });

        var currentLinks = document.querySelectorAll('a[href*="watch?v="]');
        var currentIds = new Set();
        currentLinks.forEach(function(a) {
            var m = (a.getAttribute('href') || '').match(/[?&]v=([^&]+)/);
            if (m) currentIds.add(m[1]);
        });

        if (currentIds.size > lastCount) {
            console.log("Zaladowano: " + currentIds.size + " filmow...");
            lastCount = currentIds.size;
            noChange = 0;
        } else {
            noChange++;
        }
    }

    var links = document.querySelectorAll('a[href*="watch?v="]');
    var videos = [];
    var seen = new Set();

    links.forEach(function(a) {
        var href = a.getAttribute('href') || '';
        var match = href.match(/[?&]v=([^&]+)/);
        if (!match) return;
        var id = match[1];
        if (seen.has(id)) return;

        var title = (a.getAttribute('title') || a.innerText || '').trim();
        if (!title || title.length < 2 || title.match(/^[0-9:]+$/)) {
            var container = a.closest('ytd-playlist-video-renderer, ytd-rich-item-renderer, ytd-video-renderer, ytd-grid-video-renderer') || a.parentElement;
            if (container) {
                var titleNode = container.querySelector('#video-title') || container.querySelector('h3');
                if (titleNode) {
                    title = (titleNode.getAttribute('title') || titleNode.innerText || '').trim();
                }
            }
        }

        if (!title || title.match(/^[0-9:]+$/)) {
            title = "Video " + id;
        }

        seen.add(id);
        videos.push({
            id: id,
            title: title,
            url: "https://www.youtube.com/watch?v=" + id
        });
    });

    console.log("Zapisywanie " + videos.length + " filmow do favourites.json...");
    var blob = new Blob([JSON.stringify(videos, null, 2)], { type: "application/json" });
    var dl = document.createElement("a");
    dl.href = URL.createObjectURL(blob);
    dl.download = "favourites.json";
    document.body.appendChild(dl);
    dl.click();
    document.body.removeChild(dl);
    console.log("Gotowe! Plik favourites.json zostal pobrany.");
})();
