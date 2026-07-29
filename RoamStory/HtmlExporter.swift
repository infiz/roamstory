import Photos
import SwiftUI
import UIKit

enum HtmlExportError: LocalizedError {
    case noSections

    var errorDescription: String? {
        "Select at least one section to export."
    }
}

struct HtmlExporter {
    private struct BuildContext {
        var entries: [(String, Data)] = []
        var assetIndex = 0
        var galleryIndex = 0

        mutating func addAsset(data: Data, extension fileExtension: String) -> String {
            assetIndex += 1
            let filename = "asset-\(assetIndex).\(fileExtension)"
            entries.append(("assets/\(filename)", data))
            return "assets/\(filename)"
        }

        mutating func nextGalleryID() -> String {
            galleryIndex += 1
            return "gallery-\(galleryIndex)"
        }
    }

    static func export(
        title: String,
        sections: [TripSection],
        progress: ((Double, String) -> Void)? = nil
    ) async throws -> URL {
        guard !sections.isEmpty else { throw HtmlExportError.noSections }
        progress?(0.02, "Preparing HTML package…")

        var context = BuildContext()
        var renderedSections: [(section: TripSection, html: String)] = []
        for (index, section) in sections.enumerated() {
            let sectionProgress = 0.08 + (Double(index) / Double(sections.count)) * 0.78
            progress?(sectionProgress, "Processing \(section.title)…")
            await Task.yield()
            renderedSections.append((
                section,
                await render(section: section, context: &context)
            ))
            let completedProgress = 0.08 + (Double(index + 1) / Double(sections.count)) * 0.78
            progress?(completedProgress, "Processed \(section.title)")
        }

        let pageContentPlaceholder = "<!-- ROAMSTORY_PAGE_CONTENT -->"
        let documentTemplate = """
        <!doctype html>
        <html lang="en" data-theme="dark">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(title))</title>
          <script>
            try {
              document.documentElement.dataset.theme =
                localStorage.getItem('roamstory-theme') === 'light' ? 'light' : 'dark';
            } catch {
              document.documentElement.dataset.theme = 'dark';
            }
          </script>
          <style>
            :root { color-scheme:dark; --page:#0d1117; --paper:#12161c; --panel:#1a1f26; --ink:#f0f2f4; --muted:#a9b0b9; --accent:#e76542; --line:#343b44; --link:#72a7ff; --quote:#c1c7ce; --shadow:#0006; }
            :root[data-theme="light"] { color-scheme:light; --page:#eef1f4; --paper:#f7f5f0; --panel:#fff; --ink:#1d2530; --muted:#68717c; --line:#d9d5cc; --link:#1769aa; --quote:#4f5864; --shadow:#17202c18; }
            * { box-sizing:border-box; }
            body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; background:var(--page); color:var(--ink); line-height:1.62; }
            main { width:min(900px,calc(100% - 28px)); margin:68px auto 28px; background:var(--paper); padding:clamp(18px,4vw,44px); border-radius:18px; box-shadow:0 12px 40px var(--shadow); }
            .theme-toggle { position:fixed; z-index:5; top:max(14px,env(safe-area-inset-top)); right:max(14px,env(safe-area-inset-right)); padding:9px 13px; border:1px solid var(--line); border-radius:999px; background:var(--panel); color:var(--ink); box-shadow:0 2px 10px var(--shadow); font:600 .88rem system-ui; cursor:pointer; }
            h1 { font-family:Georgia,serif; font-size:clamp(2rem,6vw,3.8rem); line-height:1.08; margin:0 0 2rem; }
            h2 { font-family:Georgia,serif; font-size:2rem; margin:2.6rem 0 .25rem; padding-top:1.5rem; border-top:1px solid var(--line); }
            h3 { font-size:1.25rem; margin:1.7rem 0 .45rem; }
            .meta,.caption,.coordinates { color:var(--muted); font-size:.9rem; }
            .block { display:block; width:100%; max-width:100%; margin:10px 0; padding:12px; overflow:hidden; border:1px solid var(--line); border-radius:14px; background:var(--panel); box-shadow:0 1px 3px #17202c0d; }
            .block > :first-child { margin-top:0; }
            .block > :last-child { margin-bottom:0; }
            .block h3 { margin:0 0 .55rem; }
            .block p { margin:.45rem 0; }
            .map-card { margin:24px 0; }
            .map-heading { display:flex; justify-content:space-between; gap:16px; margin-bottom:8px; align-items:baseline; }
            .map-heading h3 { margin:0; }
            .map-heading a { white-space:nowrap; }
            .published-map { display:block; width:100%; height:360px; border:1px solid var(--line); border-radius:12px; background:#171b21; }
            img,video { display:block; width:100%; max-width:100%; height:auto; max-height:70vh; object-fit:contain; border-radius:12px; background:#101722; }
            .gallery-slider { position:relative; width:100%; max-width:100%; border-radius:12px; overflow:hidden; background:#05070a; }
            .gallery-track { display:flex; overflow-x:auto; scroll-snap-type:x mandatory; scrollbar-width:none; overscroll-behavior-x:contain; }
            .gallery-track::-webkit-scrollbar { display:none; }
            .gallery-slide { flex:0 0 100%; scroll-snap-align:center; scroll-snap-stop:always; display:flex; flex-direction:column; justify-content:center; min-width:0; }
            .gallery-slide img { width:100%; height:clamp(260px,70vh,640px); object-fit:contain; border-radius:0; background:#05070a; cursor:zoom-in; }
            .gallery-photo-caption { margin:0; padding:10px 18px 46px; color:#d0d5dd; font-size:.9rem; text-align:center; background:#05070a; }
            .gallery-button { position:absolute; z-index:2; top:50%; translate:0 -50%; width:42px; height:42px; border:0; border-radius:50%; background:#17202ccc; color:white; font-size:1.5rem; cursor:pointer; }
            .gallery-button:disabled { opacity:.28; cursor:default; }
            .gallery-previous { left:12px; }
            .gallery-next { right:12px; }
            .gallery-dots { position:absolute; z-index:2; left:50%; bottom:12px; translate:-50% 0; display:flex; gap:7px; padding:7px 9px; border-radius:999px; background:#17202c99; }
            .gallery-dot { width:8px; height:8px; padding:0; border:0; border-radius:50%; background:#ffffff80; cursor:pointer; }
            .gallery-dot[aria-current="true"] { background:white; transform:scale(1.2); }
            .gallery-play { position:absolute; z-index:3; top:12px; right:12px; width:40px; height:40px; border:0; border-radius:50%; background:#000b; color:white; cursor:pointer; }
            html.lightbox-open, html.lightbox-open body { overflow:hidden; overscroll-behavior:none; }
            .photo-lightbox { width:100vw; height:100vh; max-width:none; max-height:none; margin:0; padding:0; border:0; background:#05070a; overflow:hidden; }
            .photo-lightbox::backdrop { background:#05070a; }
            .photo-lightbox img { position:fixed; inset:0; width:100%; height:100%; object-fit:contain; border-radius:0; background:#05070a; }
            .photo-lightbox > img:not(.lightbox-transition-image) { z-index:0; }
            .lightbox-transition-image { z-index:1; pointer-events:none; }
            .lightbox-close { position:fixed; z-index:4; top:max(16px,env(safe-area-inset-top)); right:max(16px,env(safe-area-inset-right)); width:44px; height:44px; border:0; border-radius:50%; background:#ffffffdc; color:#111820; font-size:1.6rem; line-height:1; cursor:pointer; }
            .lightbox-button { position:fixed; z-index:4; top:50%; translate:0 -50%; width:42px; height:42px; border:0; border-radius:50%; background:#17202ccc; color:white; font-size:1.5rem; cursor:pointer; }
            .lightbox-button:disabled, .lightbox-button[hidden] { display:none; }
            .lightbox-previous { left:max(16px,env(safe-area-inset-left)); }
            .lightbox-next { right:max(16px,env(safe-area-inset-right)); }
            .lightbox-position { position:fixed; z-index:4; left:50%; bottom:max(18px,env(safe-area-inset-bottom)); translate:-50% 0; padding:7px 12px; border-radius:999px; background:#000a; color:white; font-size:.9rem; }
            .lightbox-position[hidden] { display:none; }
            .lightbox-caption { position:fixed; z-index:4; left:50%; bottom:max(62px,calc(env(safe-area-inset-bottom) + 62px)); translate:-50% 0; width:min(680px,calc(100% - 40px)); padding:9px 13px; border-radius:10px; background:#000a; color:white; text-align:center; }
            .lightbox-info-button { position:fixed; z-index:4; top:max(16px,env(safe-area-inset-top)); right:max(72px,calc(env(safe-area-inset-right) + 72px)); width:44px; height:44px; border:0; border-radius:50%; background:#ffffffdc; color:#111820; cursor:pointer; }
            .lightbox-play-button { position:fixed; z-index:4; top:max(16px,env(safe-area-inset-top)); right:max(128px,calc(env(safe-area-inset-right) + 128px)); width:44px; height:44px; border:0; border-radius:50%; background:#ffffffdc; color:#111820; cursor:pointer; }
            .lightbox-play-button[hidden] { display:none; }
            .lightbox-metadata { position:fixed; z-index:4; right:0; top:76px; width:min(340px,90vw); padding:16px; background:#12161cee; color:white; border-radius:12px 0 0 12px; line-height:1.7; }
            .lightbox-metadata div { display:flex; gap:9px; align-items:center; font-variant-numeric:tabular-nums; }
            .lightbox-metadata span { width:1.4rem; text-align:center; }
            .lightbox-metadata[hidden] { display:none; }
            blockquote { margin:.25rem 0; padding:.5rem 1.2rem; border-left:4px solid var(--accent); color:var(--quote); }
            pre { width:100%; margin:0; overflow:auto; padding:1rem; border-radius:10px; background:#18202b; color:#f4f6f8; font:14px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace; }
            hr { width:100%; border:0; border-top:1px solid var(--line); margin:0; }
            a { color:var(--link); text-decoration-thickness:.08em; }
            .linked-media { position:relative; display:block; }
            .photo-viewer-image { cursor:zoom-in; }
            .media-link-badge { position:absolute; z-index:2; top:10px; right:10px; width:38px; height:38px; display:grid; place-items:center; border-radius:50%; background:#1769aae8; color:white; font-size:1.15rem; font-weight:700; text-decoration:none; box-shadow:0 2px 8px #0005; }
            .section-navigation { display:flex; gap:8px; margin:0 0 26px; padding:4px 0 10px; overflow-x:auto; scrollbar-width:thin; }
            .section-navigation a { flex:0 0 auto; padding:7px 12px; border:1px solid var(--line); border-radius:999px; background:var(--panel); text-decoration:none; }
            .section-navigation a[aria-current="page"] { border-color:var(--accent); color:var(--ink); }
            .section-index { display:grid; gap:12px; }
            .section-index-entry { display:block; padding:16px; border:1px solid var(--line); border-radius:14px; background:var(--panel); color:var(--ink); }
            .section-index-title { display:flex; gap:9px; align-items:center; color:var(--ink); font-weight:700; text-decoration:none; }
            .section-location-link { color:var(--muted); text-decoration:underline; text-underline-offset:2px; }
            .section-index-meta { display:flex; flex-wrap:wrap; gap:6px 12px; margin-top:5px; color:var(--muted); font-size:.9rem; }
            .section-detail-meta { display:flex; flex-wrap:wrap; gap:6px 12px; align-items:center; margin:0 0 18px; color:var(--muted); font-size:.9rem; }
            @media print { body { background:white; } main { width:100%; margin:0; padding:0; box-shadow:none; } .theme-toggle { display:none; } section { break-inside:avoid-page; } }
          </style>
        </head>
        <body>
          <button class="theme-toggle" type="button" aria-label="Switch to light theme">☀ Light</button>
          <main>
            <h1>\(htmlEscape(title))</h1>
            \(pageContentPlaceholder)
          </main>
          <dialog class="photo-lightbox" aria-label="Full-screen photo">
            <button class="lightbox-close" type="button" aria-label="Close full-screen photo">×</button>
            <button class="lightbox-info-button" type="button" aria-label="Show photo information">ⓘ</button>
            <button class="lightbox-play-button" type="button" aria-label="Play automatic slideshow">▶</button>
            <button class="lightbox-button lightbox-previous" type="button" aria-label="Previous full-screen photo">‹</button>
            <img alt="">
            <button class="lightbox-button lightbox-next" type="button" aria-label="Next full-screen photo">›</button>
            <div class="lightbox-caption" aria-live="polite"></div>
            <div class="lightbox-position" aria-live="polite"></div>
            <div class="lightbox-metadata" hidden></div>
          </dialog>
          <script>
            const themeToggle = document.querySelector('.theme-toggle');
            const localDateTime = new Intl.DateTimeFormat(undefined, {
              dateStyle: 'medium',
              timeStyle: 'short'
            });
            document.querySelectorAll('.local-time-range').forEach((element) => {
              const start = element.dataset.start ? new Date(element.dataset.start) : null;
              const end = element.dataset.end ? new Date(element.dataset.end) : null;
              if (start && end) {
                element.textContent = `${localDateTime.format(start)} – ${localDateTime.format(end)}`;
              } else if (start) {
                element.textContent = localDateTime.format(start);
              }
            });
            const updateThemeToggle = () => {
              const isLight = document.documentElement.dataset.theme === 'light';
              themeToggle.textContent = isLight ? '☾ Dark' : '☀ Light';
              themeToggle.setAttribute('aria-label', isLight ? 'Switch to dark theme' : 'Switch to light theme');
            };
            themeToggle.addEventListener('click', () => {
              const nextTheme = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
              document.documentElement.dataset.theme = nextTheme;
              try { localStorage.setItem('roamstory-theme', nextTheme); } catch {}
              updateThemeToggle();
            });
            updateThemeToggle();
            const lightbox = document.querySelector('.photo-lightbox');
            const lightboxImage = lightbox.querySelector('img');
            const lightboxPrevious = lightbox.querySelector('.lightbox-previous');
            const lightboxNext = lightbox.querySelector('.lightbox-next');
            const lightboxCaption = lightbox.querySelector('.lightbox-caption');
            const lightboxPosition = lightbox.querySelector('.lightbox-position');
            const lightboxMetadata = lightbox.querySelector('.lightbox-metadata');
            const lightboxInfo = lightbox.querySelector('.lightbox-info-button');
            const lightboxPlay = lightbox.querySelector('.lightbox-play-button');
            let lightboxImages = [];
            let lightboxIndex = 0;
            let lightboxTouchStart = null;
            let lightboxSlideshowTimer;
            let isLightboxTransitioning = false;
            const stopLightboxSlideshow = () => {
              clearInterval(lightboxSlideshowTimer);
              lightboxSlideshowTimer = undefined;
              lightboxPlay.textContent = '▶';
              lightboxPlay.setAttribute('aria-label', 'Play automatic slideshow');
            };
            const closeLightbox = () => {
              stopLightboxSlideshow();
              lightbox.close();
            };
            const openLightbox = () => {
              lightbox.showModal();
              document.documentElement.classList.add('lightbox-open');
            };
            const formatBytes = (value) => {
              const bytes = Number(value);
              if (!Number.isFinite(bytes)) return null;
              const units = ['B', 'KB', 'MB', 'GB'];
              let size = bytes;
              let unitIndex = 0;
              while (size >= 1_000 && unitIndex < units.length - 1) {
                size /= 1_000;
                unitIndex += 1;
              }
              return `${size.toFixed(unitIndex ? 1 : 0)} ${units[unitIndex]}`;
            };
            const updateLightbox = () => {
              const image = lightboxImages[lightboxIndex];
              if (!image) return;
              lightboxImage.src = image.src;
              lightboxImage.alt = image.alt;
              lightboxCaption.textContent = image.dataset.caption || '';
              lightboxCaption.hidden = !image.dataset.caption;
              lightboxPosition.textContent = `${lightboxIndex + 1} of ${lightboxImages.length}`;
              const isGallery = lightboxImages.length > 1;
              lightboxPrevious.hidden = !isGallery;
              lightboxNext.hidden = !isGallery;
              lightboxPosition.hidden = !isGallery;
              lightboxPlay.hidden = !isGallery;
              const details = [];
              if (image.dataset.takenAt) {
                try {
                  details.push(['🗓', new Intl.DateTimeFormat(undefined, {
                    dateStyle:'medium',
                    timeStyle:'medium'
                  }).format(new Date(image.dataset.takenAt))]);
                } catch {
                  details.push(['🗓', image.dataset.takenAt]);
                }
              }
              if (image.dataset.byteSize) {
                details.push(['▣', formatBytes(image.dataset.byteSize)]);
              }
              if (image.dataset.pixelWidth && image.dataset.pixelHeight) {
                details.push([
                  '↔',
                  `${image.dataset.pixelWidth} × ${image.dataset.pixelHeight} px`
                ]);
              }
              lightboxMetadata.replaceChildren(...details.map(([icon, text]) => {
                const row = document.createElement('div');
                const symbol = document.createElement('span');
                symbol.setAttribute('aria-hidden', 'true');
                symbol.textContent = icon;
                row.append(symbol, document.createTextNode(text));
                return row;
              }));
            };
            const transitionLightbox = async (direction) => {
              if (isLightboxTransitioning || lightboxImages.length < 2) return;
              isLightboxTransitioning = true;
              const nextIndex = (
                lightboxIndex + direction + lightboxImages.length
              ) % lightboxImages.length;
              const nextSource = lightboxImages[nextIndex];
              const incoming = lightboxImage.cloneNode();
              incoming.className = 'lightbox-transition-image';
              incoming.src = nextSource.src;
              incoming.alt = nextSource.alt;
              lightbox.appendChild(incoming);
              const duration = 700;
              const outgoingAnimation = lightboxImage.animate([
                { transform: 'translateX(0)' },
                { transform: `translateX(${-direction * 100}%)` }
              ], { duration, easing: 'cubic-bezier(.25,.1,.25,1)' });
              const incomingAnimation = incoming.animate([
                { transform: `translateX(${direction * 100}%)` },
                { transform: 'translateX(0)' }
              ], { duration, easing: 'cubic-bezier(.25,.1,.25,1)' });
              await Promise.allSettled([
                outgoingAnimation.finished,
                incomingAnimation.finished
              ]);
              lightboxIndex = nextIndex;
              updateLightbox();
              incoming.remove();
              isLightboxTransitioning = false;
            };
            const showPreviousLightboxPhoto = () => transitionLightbox(-1);
            const showNextLightboxPhoto = () => transitionLightbox(1);
            lightbox.querySelector('.lightbox-close').addEventListener('click', closeLightbox);
            lightboxInfo.addEventListener('click', () => {
              lightboxMetadata.hidden = !lightboxMetadata.hidden;
              lightboxInfo.setAttribute(
                'aria-label',
                lightboxMetadata.hidden ? 'Show photo information' : 'Hide photo information'
              );
            });
            lightboxPrevious.addEventListener('click', () => {
              stopLightboxSlideshow();
              showPreviousLightboxPhoto();
            });
            lightboxNext.addEventListener('click', () => {
              stopLightboxSlideshow();
              showNextLightboxPhoto();
            });
            lightboxPlay.addEventListener('click', () => {
              if (lightboxSlideshowTimer) {
                stopLightboxSlideshow();
              } else {
                lightboxPlay.textContent = '❚❚';
                lightboxPlay.setAttribute('aria-label', 'Pause automatic slideshow');
                lightboxSlideshowTimer = setInterval(showNextLightboxPhoto, 3_000);
              }
            });
            lightbox.addEventListener('click', (event) => {
              if (event.target === lightbox) closeLightbox();
            });
            lightbox.addEventListener('close', () => {
              stopLightboxSlideshow();
              document.documentElement.classList.remove('lightbox-open');
            });
            lightbox.addEventListener('keydown', (event) => {
              if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
                stopLightboxSlideshow();
              }
              if (event.key === 'ArrowLeft') showPreviousLightboxPhoto();
              if (event.key === 'ArrowRight') showNextLightboxPhoto();
            });
            lightbox.addEventListener('touchstart', (event) => {
              lightboxTouchStart = event.changedTouches[0].clientX;
            }, { passive: true });
            lightbox.addEventListener('touchend', (event) => {
              if (lightboxTouchStart === null) return;
              const distance = event.changedTouches[0].clientX - lightboxTouchStart;
              lightboxTouchStart = null;
              if (Math.abs(distance) > 45) stopLightboxSlideshow();
              if (distance > 45) showPreviousLightboxPhoto();
              if (distance < -45) showNextLightboxPhoto();
            }, { passive: true });

            document.querySelectorAll('.gallery-slider').forEach((gallery) => {
              const track = gallery.querySelector('.gallery-track');
              const slides = Array.from(track.children);
              const previous = gallery.querySelector('.gallery-previous');
              const next = gallery.querySelector('.gallery-next');
              const dots = gallery.querySelector('.gallery-dots');
              const play = gallery.querySelector('.gallery-play');
              const galleryImages = Array.from(
                gallery.querySelectorAll('.gallery-slide img')
              );
              let activeIndex = 0;
              let slideshowTimer;
              let scrollSettledTimer;

              const show = (index, direction = 0) => {
                const circularIndex = (index + slides.length) % slides.length;
                let physicalIndex = circularIndex + 1;
                if (direction > 0 && activeIndex === slides.length - 1) {
                  physicalIndex = slides.length + 1;
                } else if (direction < 0 && activeIndex === 0) {
                  physicalIndex = 0;
                }
                track.scrollTo({
                  left: physicalIndex * track.clientWidth,
                  behavior: 'smooth'
                });
              };

              const stopSlideshow = () => {
                clearInterval(slideshowTimer);
                slideshowTimer = undefined;
                play.textContent = '▶';
                play.setAttribute('aria-label', 'Play automatic slideshow');
              };

              slides.forEach((_, index) => {
                const dot = document.createElement('button');
                dot.className = 'gallery-dot';
                dot.type = 'button';
                dot.setAttribute('aria-label', `Show photo ${index + 1}`);
                dot.addEventListener('click', () => {
                  stopSlideshow();
                  show(index, 0);
                });
                dots.appendChild(dot);
              });

              if (slides.length > 1) {
                const firstClone = slides[0].cloneNode(true);
                const lastClone = slides[slides.length - 1].cloneNode(true);
                firstClone.setAttribute('aria-hidden', 'true');
                lastClone.setAttribute('aria-hidden', 'true');
                track.prepend(lastClone);
                track.append(firstClone);
                requestAnimationFrame(() => {
                  track.scrollTo({ left: track.clientWidth, behavior: 'auto' });
                });
              }

              const update = () => {
                const physicalIndex = Math.round(
                  track.scrollLeft / Math.max(track.clientWidth, 1)
                );
                activeIndex = physicalIndex <= 0
                  ? slides.length - 1
                  : physicalIndex >= slides.length + 1
                    ? 0
                    : physicalIndex - 1;
                Array.from(dots.children).forEach((dot, index) => {
                  dot.setAttribute('aria-current', index === activeIndex ? 'true' : 'false');
                });
                clearTimeout(scrollSettledTimer);
                scrollSettledTimer = setTimeout(() => {
                  const page = Math.round(
                    track.scrollLeft / Math.max(track.clientWidth, 1)
                  );
                  if (page === 0) {
                    track.scrollTo({
                      left: slides.length * track.clientWidth,
                      behavior: 'auto'
                    });
                  } else if (page === slides.length + 1) {
                    track.scrollTo({ left: track.clientWidth, behavior: 'auto' });
                  }
                }, 120);
              };

              previous.addEventListener('click', () => {
                stopSlideshow();
                show(activeIndex - 1, -1);
              });
              next.addEventListener('click', () => {
                stopSlideshow();
                show(activeIndex + 1, 1);
              });
              play.addEventListener('click', () => {
                if (slideshowTimer) {
                  stopSlideshow();
                  return;
                }
                play.textContent = '❚❚';
                play.setAttribute('aria-label', 'Pause automatic slideshow');
                slideshowTimer = setInterval(() => show(activeIndex + 1, 1), 3_000);
              });
              track.addEventListener('scroll', update, { passive: true });
              window.addEventListener('resize', () => {
                track.scrollTo({
                  left: (activeIndex + 1) * track.clientWidth,
                  behavior: 'auto'
                });
                update();
              });
              galleryImages.forEach((image, index) => {
                image.addEventListener('click', () => {
                  lightboxImages = galleryImages;
                  lightboxIndex = index;
                  updateLightbox();
                  openLightbox();
                });
              });
              update();
            });

            document.querySelectorAll('.photo-viewer-image').forEach((image) => {
              image.addEventListener('click', () => {
                lightboxImages = [image];
                lightboxIndex = 0;
                updateLightbox();
                openLightbox();
              });
            });
          </script>
        </body>
        </html>
        """

        func pageName(for section: TripSection) -> String {
            "section-\(section.id.uuidString.lowercased()).html"
        }
        func navigation(currentSectionID: UUID?) -> String {
            var links = "<nav class=\"section-navigation\" aria-label=\"Trip sections\"><a href=\"index.html\"\(currentSectionID == nil ? " aria-current=\"page\"" : "")>Trip</a>"
            for item in renderedSections {
                let current = item.section.id == currentSectionID ? " aria-current=\"page\"" : ""
                links += "<a href=\"\(pageName(for: item.section))\"\(current)>\(htmlEscape(item.section.title))</a>"
            }
            return links + "</nav>"
        }

        let sectionIndex = renderedSections.map { item in
            let kind = sectionKindPresentation(item.section.kind)
            let place = item.section.placeName.isEmpty
                ? ""
                : "<a class=\"section-location-link\" href=\"\(sectionGoogleMapsURL(item.section))\" target=\"_blank\" rel=\"noopener noreferrer\">\(htmlEscape(item.section.placeName))</a>"
            return """
            <div class="section-index-entry">
              <a class="section-index-title" href="\(pageName(for: item.section))"><span aria-hidden="true">\(kind.icon)</span><span>\(htmlEscape(item.section.title))</span></a>
              <span class="section-index-meta"><span>\(htmlEscape(kind.label))</span>\(place)\(sectionTimeRangeHTML(item.section))</span>
            </div>
            """
        }.joined()
        let indexContent = navigation(currentSectionID: nil)
            + "<section class=\"section-index\" aria-label=\"Trip sections\">\(sectionIndex)</section>"
        var entries: [(String, Data)] = [(
            "index.html",
            Data(documentTemplate.replacingOccurrences(
                of: pageContentPlaceholder,
                with: indexContent
            ).utf8)
        )]
        for item in renderedSections {
            let content = navigation(currentSectionID: item.section.id) + item.html
            entries.append((
                pageName(for: item.section),
                Data(documentTemplate.replacingOccurrences(
                    of: pageContentPlaceholder,
                    with: content
                ).utf8)
            ))
        }
        entries.append(contentsOf: context.entries)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedFilename(title))-HTML-\(UUID().uuidString.prefix(8)).zip")
        progress?(0.9, "Packaging HTML and media…")
        await Task.yield()
        try ZipPackageWriter.write(entries: entries, to: outputURL)
        progress?(1, "Package ready")
        return outputURL
    }

    private static func render(section: TripSection, context: inout BuildContext) async -> String {
        var blocks = ""
        for block in section.orderedBlocks {
            blocks += await render(block: block, context: &context)
        }

        let kind = sectionKindPresentation(section.kind)
        let place = section.placeName.isEmpty
            ? ""
            : "<a class=\"section-location-link\" href=\"\(sectionGoogleMapsURL(section))\" target=\"_blank\" rel=\"noopener noreferrer\">\(htmlEscape(section.placeName))</a>"

        return """
        <section>
          <h2>\(htmlEscape(section.title))</h2>
          <div class="section-detail-meta">
            <span aria-hidden="true">\(kind.icon)</span><span>\(htmlEscape(kind.label))</span>\(place)\(sectionTimeRangeHTML(section))
          </div>
          \(blocks)
        </section>
        """
    }

    private static func sectionKindPresentation(
        _ kind: SectionKind
    ) -> (icon: String, label: String) {
        let icon = switch kind {
        case .place: "📍"
        case .activity: "🚶"
        case .foodAndDrink: "🍽"
        case .accommodation: "🛏"
        case .transit: "🚗"
        case .event: "🎟"
        case .natureAndWildlife: "🐾"
        case .reflection: "📖"
        case .other: "▦"
        }
        return (icon, kind.label)
    }

    private static func sectionTimeRangeHTML(_ section: TripSection) -> String {
        let start = section.startDate ?? section.occurredAt
        guard start != nil || section.endDate != nil else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startAttribute = start.map {
            " data-start=\"\(formatter.string(from: $0))\""
        } ?? ""
        let endAttribute = section.endDate.map {
            " data-end=\"\(formatter.string(from: $0))\""
        } ?? ""
        return "<span class=\"local-time-range\"\(startAttribute)\(endAttribute)></span>"
    }

    private static func sectionGoogleMapsURL(_ section: TripSection) -> String {
        if let latitude = section.latitude,
           let longitude = section.longitude,
           (-90 ... 90).contains(latitude),
           (-180 ... 180).contains(longitude) {
            let latitudeText = String(
                format: "%.6f",
                locale: Locale(identifier: "en_US_POSIX"),
                latitude
            )
            let longitudeText = String(
                format: "%.6f",
                locale: Locale(identifier: "en_US_POSIX"),
                longitude
            )
            return "https://www.google.com/maps/search/?api=1&amp;query=\(latitudeText)%2C\(longitudeText)"
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let query = section.placeName.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "https://www.google.com/maps/search/?api=1&amp;query=\(query)"
    }

    private static func render(block: ContentBlock, context: inout BuildContext) async -> String {
        switch block.type {
        case .heading:
            return "<div class=\"block\"><h3>\(htmlEscape(block.text))</h3></div>"
        case .paragraph:
            let title = block.title.isEmpty ? "" : "<h3>\(htmlEscape(block.title))</h3>"
            return "<div class=\"block\">\(title)<p>\(richTextHTML(block))</p></div>"
        case .quote:
            let title = block.title.isEmpty ? "" : "<h3>\(htmlEscape(block.title))</h3>"
            return "<div class=\"block\">\(title)<blockquote>\(richTextHTML(block))</blockquote></div>"
        case .divider:
            return "<div class=\"block\"><hr></div>"
        case .photo:
            guard let reference = block.orderedMediaReferences.first,
                  let image = await loadImage(reference: reference),
                  let data = image.jpegData(compressionQuality: 0.88) else {
                return "<p class=\"block meta\">Photo unavailable</p>"
            }
            let path = context.addAsset(data: data, extension: "jpg")
            let metadataAttributes = await photoMetadataAttributes(reference: reference)
            let imageHTML = """
            <img class="photo-viewer-image" src="\(path)" alt="\(attributeEscape(block.caption.isEmpty ? "Travel journal photo" : block.caption))" data-caption="\(attributeEscape(block.caption))"\(metadataAttributes)>
            """
            let linkedImage: String
            if let url = LinkAddress.normalizedURL(from: block.linkURLString) {
                linkedImage = """
                <div class="linked-media">
                  \(imageHTML)
                  <a class="media-link-badge" href="\(attributeEscape(url.absoluteString))" aria-label="Open photo link">↗</a>
                </div>
                """
            } else {
                linkedImage = imageHTML
            }
            return """
            <figure class="block">\(linkedImage)\(caption(block.caption))</figure>
            """
        case .gallery:
            var images = ""
            for reference in block.orderedMediaReferences {
                if let image = await loadImage(reference: reference),
                   let data = image.jpegData(compressionQuality: 0.86) {
                    let path = context.addAsset(data: data, extension: "jpg")
                    let metadataAttributes = await photoMetadataAttributes(reference: reference)
                    let photoCaptionText = reference.caption
                    let photoCaption = photoCaptionText.isEmpty
                        ? ""
                        : "<p class=\"gallery-photo-caption\">\(htmlEscape(photoCaptionText))</p>"
                    images += """
                    <div class="gallery-slide"><img src="\(path)" alt="\(attributeEscape(photoCaptionText.isEmpty ? "Gallery photo" : photoCaptionText))" data-caption="\(attributeEscape(photoCaptionText))"\(metadataAttributes)>\(photoCaption)</div>
                    """
                }
            }
            guard !images.isEmpty else {
                return "<p class=\"block meta\">Gallery unavailable</p>"
            }
            let galleryID = context.nextGalleryID()
            let galleryTitle = block.title.isEmpty ? "" : "<h3>\(htmlEscape(block.title))</h3>"
            return """
            <figure class="block">
              \(galleryTitle)
              <div class="gallery-slider" id="\(galleryID)" aria-label="Photo gallery">
                <div class="gallery-track">\(images)</div>
                <button class="gallery-button gallery-previous" type="button" aria-label="Previous photo">‹</button>
                <button class="gallery-button gallery-next" type="button" aria-label="Next photo">›</button>
                <button class="gallery-play" type="button" aria-label="Play automatic slideshow">▶</button>
                <div class="gallery-dots" aria-label="Choose a photo"></div>
              </div>
            </figure>
            """
        case .video:
            guard let reference = block.orderedMediaReferences.first else {
                return "<p class=\"block meta\">Video unavailable</p>"
            }
            let posterPath: String?
            if let poster = await loadImage(reference: reference),
               let posterData = poster.jpegData(compressionQuality: 0.84) {
                posterPath = context.addAsset(data: posterData, extension: "jpg")
            } else {
                posterPath = nil
            }
            if let video = await loadVideo(reference: reference) {
                let path = context.addAsset(data: video.data, extension: video.fileExtension)
                let poster = posterPath.map { " poster=\"\($0)\"" } ?? ""
                return """
                <figure class="block"><video controls preload="metadata"\(poster)><source src="\(path)"></video>\(caption(block.caption))</figure>
                """
            }
            return posterPath.map {
                "<figure class=\"block\"><img src=\"\($0)\" alt=\"Video poster frame\">\(caption(block.caption))<p class=\"meta\">Video file unavailable</p></figure>"
            } ?? "<p class=\"block meta\">Video unavailable</p>"
        case .map:
            guard let section = block.section,
                  let latitude = section.latitude,
                  let longitude = section.longitude,
                  (-90 ... 90).contains(latitude),
                  (-180 ... 180).contains(longitude) else {
                return "<p class=\"block meta\">Map unavailable</p>"
            }
            let locationName = section.placeName.isEmpty
                ? (section.title.isEmpty ? "Location" : section.title)
                : section.placeName
            let latitudeText = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), latitude)
            let longitudeText = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), longitude)
            let embedURL = "https://www.google.com/maps?q=\(latitudeText)%2C\(longitudeText)&amp;z=15&amp;output=embed"
            let mapURL = "https://www.google.com/maps/search/?api=1&amp;query=\(latitudeText)%2C\(longitudeText)"
            return """
            <div class="block map-card">
              <div class="map-heading">
                <h3>\(htmlEscape(locationName))</h3>
                <a href="\(mapURL)" target="_blank" rel="noopener noreferrer">Open map</a>
              </div>
              <iframe class="published-map" title="Map of \(attributeEscape(locationName))" loading="lazy" referrerpolicy="no-referrer" src="\(embedURL)"></iframe>
              <p class="coordinates">\(String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude)), \(String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), longitude))</p>
              <p>\(htmlEscape(block.mapDescription).replacingOccurrences(of: "\n", with: "<br>"))</p>
            </div>
            """
        }
    }

    private static func richTextHTML(_ block: ContentBlock) -> String {
        guard let data = block.attributedTextData,
              let attributed = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSAttributedString.self,
                from: data
              ) else {
            return htmlEscape(block.text).replacingOccurrences(of: "\n", with: "<br>")
        }

        var result = ""
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length)
        ) { attributes, range, _ in
            var value = htmlEscape(attributed.attributedSubstring(from: range).string)
                .replacingOccurrences(of: "\n", with: "<br>")
            if let font = attributes[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { value = "<strong>\(value)</strong>" }
                if traits.contains(.traitItalic) { value = "<em>\(value)</em>" }
                value = "<span style=\"font-family:\(attributeEscape(font.familyName));font-size:\(Int(font.pointSize))px\">\(value)</span>"
            }
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                value = "<u>\(value)</u>"
            }
            if let url = attributes[.link] as? URL {
                value = "<a href=\"\(attributeEscape(url.absoluteString))\">\(value)</a>"
            }
            result += value
        }
        return result
    }

    private static func loadImage(reference: MediaReference) async -> UIImage? {
        guard await PhotoLibraryAccess.isAuthorized() else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [reference.localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 2200, height: 2200),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded, !didResume {
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    private static func loadVideo(reference: MediaReference) async -> (data: Data, fileExtension: String)? {
        guard await PhotoLibraryAccess.isAuthorized() else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [reference.localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .video || $0.type == .fullSizeVideo
        }) else { return nil }

        let rawExtension = URL(fileURLWithPath: resource.originalFilename).pathExtension.lowercased()
        let safeExtension = !rawExtension.isEmpty
            && rawExtension.count <= 5
            && rawExtension.allSatisfy { $0.isLetter || $0.isNumber }
            ? rawExtension
            : "mov"
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-\(UUID().uuidString).\(safeExtension)")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let succeeded: Bool = await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: temporaryURL,
                options: options
            ) { error in
                continuation.resume(returning: error == nil)
            }
        }
        guard succeeded, let data = try? Data(contentsOf: temporaryURL) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return nil
        }
        try? FileManager.default.removeItem(at: temporaryURL)
        return (data, safeExtension)
    }

    private static func caption(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return "<figcaption class=\"caption\">\(htmlEscape(text).replacingOccurrences(of: "\n", with: "<br>"))</figcaption>"
    }

    private static func photoMetadataAttributes(reference: MediaReference) async -> String {
        guard let metadata = await PhotoAssetMetadataLoader.load(reference: reference) else {
            return " data-filename=\"\(attributeEscape(reference.originalFilename))\""
        }
        let formatter = ISO8601DateFormatter()
        var attributes = " data-filename=\"\(attributeEscape(reference.originalFilename))\""
        if let takenAt = metadata.takenAt {
            attributes += " data-taken-at=\"\(formatter.string(from: takenAt))\""
        }
        if let byteCount = metadata.byteCount {
            attributes += " data-byte-size=\"\(byteCount)\""
        }
        attributes += " data-pixel-width=\"\(metadata.pixelWidth)\""
        attributes += " data-pixel-height=\"\(metadata.pixelHeight)\""
        return attributes
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func attributeEscape(_ text: String) -> String {
        htmlEscape(text).replacingOccurrences(of: "\n", with: " ")
    }

    private static func sanitizedFilename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = title.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let value = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "RoamStory" : value
    }
}

struct HtmlExportView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let sections: [TripSection]
    let allowsSelection: Bool

    @State private var selectedSectionIDs: Set<UUID>
    @State private var exportedURL: URL?
    @State private var isGenerating = false
    @State private var exportProgress = 0.0
    @State private var progressLabel = ""
    @State private var errorMessage: String?

    init(title: String, sections: [TripSection], allowsSelection: Bool) {
        self.title = title
        self.sections = sections
        self.allowsSelection = allowsSelection
        _selectedSectionIDs = State(initialValue: Set(sections.map(\.id)))
    }

    private var selectedSections: [TripSection] {
        sections.filter { selectedSectionIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if allowsSelection {
                    Section("Sections to Export") {
                        ForEach(sections) { section in
                            Toggle(isOn: selectionBinding(for: section.id)) {
                                Label(section.title, systemImage: section.kind.systemImage)
                            }
                        }
                        HStack {
                            Button("Select All") {
                                selectedSectionIDs = Set(sections.map(\.id))
                                exportedURL = nil
                            }
                            Spacer()
                            Button("Clear") {
                                selectedSectionIDs.removeAll()
                                exportedURL = nil
                            }
                        }
                        .font(.caption)
                    }
                } else if let section = sections.first {
                    Section("Section") {
                        Label(section.title, systemImage: section.kind.systemImage)
                    }
                }

                Section {
                    if isGenerating {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(progressLabel)
                                    .lineLimit(1)
                                Spacer()
                                Text(exportProgress, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ProgressView(value: exportProgress, total: 1)
                                .progressViewStyle(.linear)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share HTML ZIP")
                            }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            generate()
                        } label: {
                            if isGenerating {
                                Text("Generating HTML ZIP…")
                                    .frame(maxWidth: .infinity)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "archivebox")
                                    Text("Generate HTML ZIP")
                                }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .contentShape(Rectangle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating || selectedSections.isEmpty)
                    }
                } footer: {
                    Text("Extract the ZIP on a computer and open index.html. Photos, videos, and styling are stored inside the package. Interactive Google Maps require an internet connection. Archives containing videos may be large.")
                }
            }
            .navigationTitle("Export HTML Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "The HTML package could not be generated.")
            }
        }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedSectionIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedSectionIDs.insert(id)
                } else {
                    selectedSectionIDs.remove(id)
                }
                exportedURL = nil
            }
        )
    }

    private func generate() {
        isGenerating = true
        exportProgress = 0
        progressLabel = "Preparing HTML package…"
        errorMessage = nil
        Task {
            do {
                exportedURL = try await HtmlExporter.export(
                    title: title,
                    sections: selectedSections
                ) { progress, label in
                    exportProgress = progress
                    progressLabel = label
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
