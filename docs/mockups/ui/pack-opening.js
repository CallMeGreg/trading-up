(() => {
  "use strict";

  const COMPLETION_FRACTION = 0.55;
  const TAP_SLOP = 8;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const tapSetting = document.getElementById("tap-setting");
  const autoSetting = document.getElementById("auto-setting");
  const preferencesStatus = document.getElementById("preferences-status");
  const template = document.getElementById("phone-template");

  // Fixed original cards, not a roll or a statement about pack odds.
  const cards = [
    { id: "S1-001", name: "Emberpup", element: "fire", rarity: "common", flavor: "Said to nap inside active volcanoes." },
    { id: "S1-004", name: "Pebblit", element: "rock", rarity: "common", flavor: "Its shell turns aside avalanches." },
    { id: "S1-007", name: "Wickling", element: "fire", rarity: "common", flavor: "Molten eyes see through smoke." },
    { id: "S1-002", name: "Cinderhound", element: "fire", rarity: "uncommon", flavor: "Dreams in shades of orange and gold." },
    { id: "S1-005", name: "Boulderkin", element: "rock", rarity: "uncommon", flavor: "Cracks the earth where it treads." },
    { id: "S1-048", name: "Ignarok", element: "fire", rarity: "ultra", flavor: "Hot enough to boil a river dry." }
  ];
  const cueHints = {
    clean: "Swipe to open",
    ribbon: "Slice the foil seam",
    lift: "Swipe to open"
  };
  const openingDurations = { clean: 640, ribbon: 780, lift: 1100 };

  function sliceMotion(dx, dy, width) {
    const horizontal = Math.abs(dx);
    const valid = Number.isFinite(dx) && Number.isFinite(dy) &&
      Number.isFinite(width) && width > 0 && horizontal > Math.abs(dy);
    const progress = valid ? Math.min(1, horizontal / width / COMPLETION_FRACTION) : 0;
    return { progress, complete: progress >= 1, fromRight: dx < 0 };
  }

  function cardMarkup(card, compact = false) {
    const rarity = card.rarity === "ultra" ? "Ultra rare" : card.rarity;
    const image = `<img class="card-image" src="../art/${card.id}.svg" alt="" draggable="false">`;
    if (compact) {
      return `<div class="sample-card mini ${card.rarity} ${card.element}" role="listitem">
        ${image}<span class="card-name">${card.name}</span><span class="card-rarity">${rarity}</span>
      </div>`;
    }
    return `<div class="sample-card full ${card.rarity} ${card.element}">
      <div class="card-topline"><span class="card-name">${card.name}</span><span class="element-badge ${card.element}">${card.element === "fire" ? "Fire" : "Rock"}</span></div>
      ${image}
      <div class="card-number"><span>Emberfall</span><span>${card.id.slice(-3)} / 050</span></div>
      <p class="card-flavor">${card.flavor}</p>
      <div class="card-footer"><span class="card-rarity">${rarity}</span><span class="sample-stamp">Sample card</span></div>
    </div>`;
  }

  class PackDemo {
    constructor(article) {
      this.article = article;
      this.concept = article.dataset.concept;
      this.phase = "sealed";
      this.gesture = null;
      this.timer = null;
      this.cardIndex = 0;
      article.querySelector(".phone-mount").append(template.content.cloneNode(true));
      const find = selector => article.querySelector(selector);
      this.pack = find(".foil-pack");
      this.sealedView = find(".sealed-view");
      this.revealView = find(".reveal-view");
      this.summaryView = find(".summary-view");
      this.hint = find(".gesture-hint");
      this.detail = find(".gesture-detail");
      this.output = find(".interaction-status");
      this.accessibleOpen = find(".accessible-open");
      this.nextCard = find(".next-card");
      this.route = find(".route-label");
      this.screenFooter = find(".screen-footer");
      this.phoneTitle = find(".phone-title");
      this.hint.id = `${this.concept}-hint`;
      this.detail.id = `${this.concept}-detail`;
      this.pack.setAttribute("aria-label", `Open Emberfall sample pack: ${find("h3").textContent}`);
      this.pack.setAttribute("aria-describedby", `${this.hint.id} ${this.detail.id}`);
      find(".summary-grid").innerHTML = cards.map(card => cardMarkup(card, true)).join("");

      this.pack.addEventListener("pointerdown", event => this.startDrag(event));
      this.pack.addEventListener("pointermove", event => this.moveDrag(event));
      this.pack.addEventListener("pointerup", event => this.endDrag(event));
      this.pack.addEventListener("pointercancel", event => {
        if (this.gesture?.id === event.pointerId) this.cancelDrag("Cancelled. The pack is still sealed.");
      });
      this.pack.addEventListener("lostpointercapture", event => {
        if (this.gesture?.id === event.pointerId) this.cancelDrag("Interrupted. The pack is still sealed.");
      });
      this.pack.addEventListener("keydown", event => {
        if (event.key === "Escape") {
          this.cancelDrag("Cancelled. The pack is still sealed.");
        } else if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          if (!event.repeat) {
            this.cancelDrag();
            this.open("the accessible action");
          }
        }
      });
      // AT activation has no physical pointer sequence. Wrapper taps are handled
      // on pointerup so a rejected drag can never turn into a click-to-open.
      this.pack.addEventListener("click", event => {
        if (event.detail === 0 && !event.pointerType) this.open("the accessible action");
      });
      this.pack.addEventListener("dragstart", event => event.preventDefault());
      this.accessibleOpen.addEventListener("click", () => this.open("the accessible action"));
      for (const button of article.querySelectorAll(".replay-demo, .phone-replay")) {
        button.addEventListener("click", () => {
          this.reset();
          this.pack.focus({ preventScroll: true });
        });
      }
      this.nextCard.addEventListener("click", () => {
        if (this.phase !== "revealing") return;
        if (this.cardIndex === cards.length - 1) this.showSummary(false);
        else {
          this.cardIndex += 1;
          this.renderCard();
        }
      });
      this.reset(false);
    }

    clearProgress() {
      this.pack.style.setProperty("--cut", "0");
      this.pack.style.setProperty("--trail-start", "0%");
      this.pack.style.setProperty("--trail-width", "0%");
      this.pack.style.setProperty("--finger", "0%");
      this.pack.classList.remove("is-dragging", "is-ready");
      this.pack.dataset.direction = "left";
    }

    releaseGesture() {
      const previous = this.gesture;
      this.gesture = null;
      if (previous && this.pack.hasPointerCapture(previous.id)) this.pack.releasePointerCapture(previous.id);
      return previous;
    }

    cancelDrag(message) {
      if (!this.gesture) return;
      this.releaseGesture();
      this.clearProgress();
      this.refreshPreferences();
      if (message) this.output.textContent = message;
    }

    startDrag(event) {
      if (event.isPrimary === false) {
        this.cancelDrag("Multi-touch cancelled the slice. Try again with one finger.");
        return;
      }
      if (this.phase !== "sealed" || event.button !== 0 || this.gesture) return;
      const rect = this.pack.getBoundingClientRect();
      const seam = this.pack.querySelector(".seam-hit-area").getBoundingClientRect();
      this.gesture = {
        id: event.pointerId,
        x: event.clientX,
        y: event.clientY,
        left: rect.left,
        width: rect.width,
        atSeam: event.clientY >= seam.top && event.clientY <= seam.bottom,
        maxTravel: 0
      };
      this.pack.focus({ preventScroll: true });
      this.pack.setPointerCapture(event.pointerId);
    }

    dragMotion(event) {
      const gesture = this.gesture;
      const dx = event.clientX - gesture.x;
      const dy = event.clientY - gesture.y;
      gesture.maxTravel = Math.max(gesture.maxTravel, Math.hypot(dx, dy));
      return { ...sliceMotion(dx, dy, gesture.width), dx, dy };
    }

    setHint(text) {
      this.hint.textContent = this.concept === "clean" ? "Swipe to open" : text;
    }

    moveDrag(event) {
      if (!this.gesture || event.pointerId !== this.gesture.id) return;
      const motion = this.dragMotion(event);
      if (this.gesture.maxTravel <= TAP_SLOP) return;
      if (!this.gesture.atSeam) {
        this.setHint("Start at the top seam instead.");
        return;
      }
      this.pack.classList.toggle("is-dragging", motion.progress > 0);
      this.pack.dataset.direction = motion.fromRight ? "right" : "left";
      this.pack.style.setProperty("--cut", String(motion.progress));
      const start = Math.min(1, Math.max(0, (this.gesture.x - this.gesture.left) / this.gesture.width));
      const finger = Math.min(1, Math.max(0, (event.clientX - this.gesture.left) / this.gesture.width));
      this.pack.style.setProperty("--trail-start", `${Math.min(start, finger) * 100}%`);
      this.pack.style.setProperty("--trail-width", `${motion.progress > 0 ? Math.abs(finger - start) * 100 : 0}%`);
      this.pack.style.setProperty("--finger", `${finger * 100}%`);
      this.pack.classList.toggle("is-ready", motion.complete);
      this.setHint(motion.complete ? "Release to open" :
        motion.progress > 0 ? "Keep slicing…" : "Slide along the top edge");
      this.detail.textContent = motion.complete ? "Your cards are waiting" : "Follow the seam with your finger";
    }

    endDrag(event) {
      if (!this.gesture || event.pointerId !== this.gesture.id) return;
      const motion = this.dragMotion(event);
      const gesture = this.releaseGesture();
      if (gesture.atSeam && motion.complete) {
        this.pack.dataset.direction = motion.fromRight ? "right" : "left";
        this.open(motion.fromRight ? "a right-to-left slice" : "a left-to-right slice");
      } else if (gesture.maxTravel <= TAP_SLOP) {
        this.clearProgress();
        if (tapSetting.checked) this.open("a wrapper tap");
        else {
          this.refreshPreferences();
          this.output.textContent = "Tap is off. Slice the top seam, or use the accessible open action.";
        }
      } else {
        this.clearProgress();
        this.refreshPreferences();
        this.output.textContent = !gesture.atSeam ? "Reset. Start your drag on the top seam." :
          Math.abs(motion.dy) >= Math.abs(motion.dx) ? "Vertical drag reset. Slice left or right across the seam." :
            "Short slice reset. Drag at least 55% of the wrapper width, then release.";
      }
    }

    refreshPreferences() {
      if (this.phase !== "sealed") return;
      this.pack.dataset.tap = tapSetting.checked ? "on" : "off";
      this.setHint(cueHints[this.concept]);
      this.detail.textContent = tapSetting.checked ? "Or tap the pack" : "Across the top, in either direction";
      this.route.textContent = autoSetting.checked ? "Auto open · straight to summary" : "Card-by-card reveal";
      this.screenFooter.classList.toggle("is-auto", autoSetting.checked);
    }

    reset(announce = true) {
      window.clearTimeout(this.timer);
      this.timer = null;
      this.releaseGesture();
      this.phase = "sealed";
      this.article.dataset.phase = "sealed";
      this.cardIndex = 0;
      this.sealedView.hidden = false;
      this.revealView.hidden = true;
      this.summaryView.hidden = true;
      this.pack.classList.remove("is-opening");
      this.clearProgress();
      this.pack.setAttribute("aria-disabled", "false");
      this.pack.tabIndex = 0;
      this.accessibleOpen.disabled = false;
      this.phoneTitle.textContent = "Emberfall";
      this.refreshPreferences();
      if (announce) this.output.textContent = "Resealed. Same six-card sample; your settings are unchanged.";
    }

    open(source) {
      if (this.phase !== "sealed") return;
      this.releaseGesture();
      this.phase = "opening";
      this.article.dataset.phase = "opening";
      this.openSource = source;
      this.openWithAuto = autoSetting.checked;
      if (document.activeElement === this.accessibleOpen) this.pack.focus({ preventScroll: true });
      this.pack.setAttribute("aria-disabled", "true");
      this.pack.tabIndex = -1;
      this.accessibleOpen.disabled = true;
      this.output.textContent = `Opened with ${source}.`;
      if (this.openWithAuto || reducedMotion.matches) this.finishOpening();
      else {
        this.pack.style.setProperty("--cut", "1");
        this.pack.classList.remove("is-dragging", "is-ready");
        this.pack.classList.add("is-opening");
        this.setHint(this.concept === "lift" ? "A little anticipation…" : "Let’s see what’s inside.");
        this.detail.textContent = "";
        this.timer = window.setTimeout(() => this.finishOpening(), openingDurations[this.concept]);
      }
    }

    shouldMoveFocus() {
      return this.article.contains(document.activeElement) &&
        (this.pack === document.activeElement || this.accessibleOpen === document.activeElement ||
          this.nextCard === document.activeElement);
    }

    finishOpening() {
      window.clearTimeout(this.timer);
      this.timer = null;
      if (this.phase !== "opening") return;
      if (this.openWithAuto) this.showSummary(true);
      else {
        const moveFocus = this.shouldMoveFocus();
        this.phase = "revealing";
        this.article.dataset.phase = "revealing";
        this.sealedView.hidden = true;
        this.revealView.hidden = false;
        this.summaryView.hidden = true;
        this.phoneTitle.textContent = "Your new cards";
        this.route.textContent = "Card-by-card reveal";
        this.screenFooter.classList.remove("is-auto");
        this.renderCard();
        if (moveFocus) this.article.querySelector(".reveal-heading").focus({ preventScroll: true });
      }
    }

    renderCard() {
      const card = cards[this.cardIndex];
      this.article.querySelector(".card-count").textContent = `Card ${this.cardIndex + 1} of ${cards.length}`;
      this.article.querySelector(".reveal-art").innerHTML = cardMarkup(card);
      this.article.querySelector(".reveal-dots").innerHTML = cards.map((_, index) =>
        `<span class="${index === this.cardIndex ? "active" : index < this.cardIndex ? "seen" : ""}"></span>`
      ).join("");
      this.nextCard.textContent = this.cardIndex === cards.length - 1 ? "See pack summary →" : "Reveal next card →";
      this.output.textContent = `Card ${this.cardIndex + 1} of ${cards.length}: ${card.name}, ${card.rarity === "ultra" ? "ultra rare" : card.rarity}.`;
    }

    showSummary(automatic) {
      const moveFocus = this.shouldMoveFocus();
      this.phase = "summary";
      this.article.dataset.phase = "summary";
      this.sealedView.hidden = true;
      this.revealView.hidden = true;
      this.summaryView.hidden = false;
      this.phoneTitle.textContent = "Pack summary";
      this.route.textContent = automatic ? "Auto open · reveal skipped" : "All six cards revealed";
      this.screenFooter.classList.toggle("is-auto", automatic);
      this.output.textContent = automatic ?
        `Opened with ${this.openSource}. Auto open took you directly to the six-card summary.` :
        "Six-card summary. Nothing has been kept, sold, or purchased.";
      if (moveFocus) this.article.querySelector(".summary-heading").focus({ preventScroll: true });
    }
  }

  // Deliberately not persisted, including browser-restored checkbox state.
  tapSetting.checked = false;
  autoSetting.checked = false;
  const demos = [...document.querySelectorAll("[data-concept]")].map(article => new PackDemo(article));

  function syncPreferences(message = "") {
    document.getElementById("tap-state").textContent = tapSetting.checked ? "On" : "Off";
    document.getElementById("auto-state").textContent = autoSetting.checked ? "On" : "Off";
    const action = tapSetting.checked ? "Tap or slice" : "Slice";
    const route = autoSetting.checked ? "six-card summary immediately." : "card-by-card reveal → six-card summary.";
    preferencesStatus.textContent = `${message}${action} → ${route}`;
    const key = `${Number(tapSetting.checked)}${Number(autoSetting.checked)}`;
    for (const row of document.querySelectorAll("[data-settings]")) row.classList.toggle("current", row.dataset.settings === key);
    for (const demo of demos) {
      demo.cancelDrag("Settings changed. The slice was reset; the pack is still sealed.");
      demo.refreshPreferences();
    }
  }

  tapSetting.addEventListener("change", () => syncPreferences());
  autoSetting.addEventListener("change", () => syncPreferences());
  document.getElementById("replay-all").addEventListener("click", () => {
    for (const demo of demos) demo.reset();
    syncPreferences("All three packs resealed. ");
  });
  document.getElementById("restore-defaults").addEventListener("click", () => {
    tapSetting.checked = false;
    autoSetting.checked = false;
    for (const demo of demos) demo.reset(false);
    for (const demo of demos) demo.output.textContent = "Defaults restored. Both settings are off; the pack is sealed.";
    syncPreferences("Defaults restored. ");
  });
  const cancelActiveDrags = () => {
    for (const demo of demos) demo.cancelDrag("Interrupted. The pack is still sealed.");
  };
  window.addEventListener("blur", cancelActiveDrags);
  window.addEventListener("resize", cancelActiveDrags);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) cancelActiveDrags();
  });
  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) for (const demo of demos) demo.finishOpening();
  });
  syncPreferences();
})();
