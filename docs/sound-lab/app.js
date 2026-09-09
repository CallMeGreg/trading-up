/* Local-only auditioning and review. No analytics, uploads, frameworks or CDNs. */
"use strict";

(() => {
  const $ = (id) => document.getElementById(id);
  const pack = globalThis.SOUND_LAB_MANIFEST;
  const storageKey = "trading-up-sound-lab-review-v1";
  const choices = new Set(["pending", "studio", "mythic", "revise", "silence"]);
  const approved = (choice) => choice === "studio" || choice === "mythic";
  const errorBox = $("error");

  function showError(error) {
    errorBox.textContent = error instanceof Error ? error.message : String(error);
    errorBox.hidden = false;
  }

  if (!pack || pack.schemaVersion !== 1 || !Array.isArray(pack.cues)) {
    showError("The sound catalogue is missing or incompatible. Run python3 tools/generate_sound_lab.py from the repository root, then reload.");
    return;
  }

  const cues = new Map(pack.cues.map((cue) => [cue.id, cue]));
  const musicPack = globalThis.SOUND_LAB_MUSIC;
  const studioApprovals = new Set();
  const reviews = new Map();
  const counters = new Map();
  const buffers = new Map();
  const voices = new Set();
  let storageWritable = true;
  let graph = null;
  let token = 0;
  let animation = 0;
  let transport = null;
  let activeCueIds = new Set();
  let musicVoice = null;
  let musicToken = 0;
  let rememberedMusicVolume = 28;
  let musicAdjustmentStart = null;

  function reviewFor(id) {
    return reviews.get(id) || {
      choice: studioApprovals.has(id) ? "studio" : "pending", note: "", revision: cues.get(id).revision,
    };
  }

  async function loadStudioApproval() {
    const response = await fetch("studio-approval.json");
    if (!response.ok) throw new Error("The Studio approval record could not be loaded. The effects remain available to review.");
    const approval = await response.json();
    if (approval.schemaVersion !== 1 || approval.direction !== "studio" || !approval.sounds) {
      throw new Error("The Studio approval record is invalid.");
    }
    for (const cue of pack.cues) {
      const hashes = approval.sounds[cue.id];
      if (Array.isArray(hashes) && hashes.length === cue.audio.studio.length &&
          hashes.every((hash, index) => hash === cue.audio.studio[index].sha256)) {
        studioApprovals.add(cue.id);
      }
    }
  }

  function reviewDocument() {
    return {
      schemaVersion: 1,
      packId: pack.id,
      packRevision: pack.revision,
      exportedAt: new Date().toISOString(),
      decisions: Object.fromEntries(pack.cues.map((cue) => [cue.id, { ...reviewFor(cue.id) }])),
    };
  }

  function parseReview(value) {
    if (!value || value.schemaVersion !== 1 || value.packId !== pack.id ||
        !value.decisions || typeof value.decisions !== "object" || Array.isArray(value.decisions)) {
      throw new Error("This is not a compatible Trading Up sound-lab review.");
    }
    const result = new Map();
    for (const [id, decision] of Object.entries(value.decisions)) {
      if (!cues.has(id)) throw new Error(`This review contains an unknown action: ${id}. Nothing was imported.`);
      if (!decision || !choices.has(decision.choice) || typeof decision.note !== "string" ||
          decision.note.length > 2000 || typeof decision.revision !== "string") {
        throw new Error(`Invalid decision for ${id}. Nothing was imported.`);
      }
      const item = { choice: decision.choice, note: decision.note, revision: cues.get(id).revision };
      if (typeof decision.updatedAt === "string" && Number.isFinite(Date.parse(decision.updatedAt))) {
        item.updatedAt = decision.updatedAt;
      }
      if (choices.has(decision.previousChoice)) item.previousChoice = decision.previousChoice;
      if (decision.revision !== cues.get(id).revision && decision.choice !== "pending") {
        item.previousChoice = decision.choice;
        item.choice = "pending";
      }
      result.set(id, item);
    }
    return result;
  }

  function persistReview() {
    if (!storageWritable) return;
    try {
      localStorage.setItem(storageKey, JSON.stringify(reviewDocument()));
      $("storage-status").textContent = "Saved in this browser. Export review JSON to preserve it outside this browser and hand back your decisions.";
    } catch (error) {
      storageWritable = false;
      $("storage-status").textContent = `Browser storage is unavailable (${error.name}). Notes are in memory only; export your review before closing.`;
      showError("Your latest choices could not be saved to browser storage. Export review to keep them.");
    }
  }

  function loadReview() {
    try {
      const saved = localStorage.getItem(storageKey);
      if (saved) {
        for (const [id, decision] of parseReview(JSON.parse(saved))) reviews.set(id, decision);
        if ([...reviews.values()].some((item) => item.previousChoice)) {
          $("storage-status").textContent = "Some cues have changed since your review. Affected choices are pending again; their previous decisions and notes are retained.";
        }
      }
    } catch (error) {
      storageWritable = false;
      $("storage-status").textContent = "The stored review was not overwritten. New notes are in memory only; export them before closing.";
      showError(`Could not load the saved review: ${error.message}`);
    }
  }

  function saveDecision(id, change) {
    const decision = { ...reviewFor(id), ...change, updatedAt: new Date().toISOString() };
    if (change.choice !== undefined) delete decision.previousChoice;
    reviews.set(id, decision);
    persistReview();
    updateReviewCount();
  }

  function updateReviewCount() {
    const values = pack.cues.map((cue) => reviewFor(cue.id));
    const count = values.filter((item) => approved(item.choice)).length;
    const revision = values.filter((item) => item.choice === "revise").length;
    const quiet = values.filter((item) => item.choice === "silence").length;
    const pending = values.filter((item) => item.choice === "pending").length;
    $("review-count").textContent = `${count} / ${pack.cues.length} approved`;
    $("review-detail").textContent = `${pending} pending / ${revision} to revise / ${quiet} prefer silence`;
  }

  function updateMonitor() {
    if (!graph) return;
    const mode = $("monitor").value;
    const now = graph.context.currentTime;
    graph.fold.channelCount = mode === "stereo" ? 2 : 1;
    graph.highpass.frequency.setTargetAtTime(mode === "phone" ? 250 : 20, now, 0.015);
    graph.lowpass.frequency.setTargetAtTime(mode === "phone" ? 6500 : 22000, now, 0.015);
  }

  async function audioGraph() {
    if (location.protocol === "file:") {
      throw new Error("Serve this folder locally for audio playback: python3 -m http.server 8766 --bind 127.0.0.1 --directory docs/sound-lab, then open http://127.0.0.1:8766. No internet connection is needed.");
    }
    if (!graph) {
      if (!globalThis.AudioContext) throw new Error("This browser does not support Web Audio. Open the soundboard in Safari, Chrome or Firefox.");
      const context = new AudioContext({ latencyHint: "interactive", sampleRate: 48000 });
      const fold = context.createGain();
      fold.channelCountMode = "explicit";
      fold.channelInterpretation = "speakers";
      const highpass = context.createBiquadFilter();
      highpass.type = "highpass";
      highpass.Q.value = 0.707;
      const lowpass = context.createBiquadFilter();
      lowpass.type = "lowpass";
      lowpass.Q.value = 0.707;
      const limiter = context.createDynamicsCompressor();
      limiter.threshold.value = -3;
      limiter.knee.value = 3;
      limiter.ratio.value = 20;
      limiter.attack.value = 0.002;
      limiter.release.value = 0.12;
      const master = context.createGain();
      master.gain.value = Number($("volume").value) / 100;
      fold.connect(highpass).connect(lowpass).connect(limiter).connect(master).connect(context.destination);
      const musicGain = context.createGain();
      musicGain.gain.value = Number($("music-volume").value) / 100;
      musicGain.connect(fold);
      graph = { context, fold, highpass, lowpass, limiter, master, musicGain };
      updateMonitor();
    }
    if (graph.context.state !== "running") await graph.context.resume();
    if (graph.context.state !== "running") throw new Error("Audio is still suspended. Click a play button again to enable playback.");
    return graph;
  }

  async function bufferFor(take) {
    const key = `${take.file}?v=${take.sha256}`;
    if (!buffers.has(key)) {
      const pending = (async () => {
        const response = await fetch(key);
        if (!response.ok) throw new Error(`Could not load ${take.file}: HTTP ${response.status}. Regenerate the sound lab if an asset is missing.`);
        const bytes = await response.arrayBuffer();
        const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
          .map((byte) => byte.toString(16).padStart(2, "0")).join("");
        if (hash !== take.sha256) throw new Error("This sound changed since the page loaded. Reload before auditioning or approving the new render.");
        return graph.context.decodeAudioData(bytes);
      })();
      buffers.set(key, pending);
      // Bound decoded-audio memory without interrupting already-scheduled sources.
      if (buffers.size > 48) buffers.delete(buffers.keys().next().value);
    }
    try {
      return await buffers.get(key);
    } catch (error) {
      buffers.delete(key);
      throw error;
    }
  }

  function setActiveCues(ids) {
    for (const id of activeCueIds) {
      if (!ids.has(id)) document.querySelector(`[data-cue="${id}"]`)?.removeAttribute("data-playing");
    }
    for (const id of ids) {
      if (!activeCueIds.has(id)) document.querySelector(`[data-cue="${id}"]`)?.setAttribute("data-playing", "true");
    }
    activeCueIds = ids;
  }

  function stopEffects() {
    token += 1;
    cancelAnimationFrame(animation);
    transport = null;
    if (graph) {
      const now = graph.context.currentTime;
      for (const voice of voices) {
        voice.gain.gain.cancelScheduledValues(now);
        voice.gain.gain.setTargetAtTime(0, now, 0.006);
        voice.source.stop(now + 0.035);
      }
    }
    setActiveCues(new Set());
    $("play-state").textContent = "Stopped / ready";
    $("now-playing").textContent = "Choose an action or a listening scene.";
    $("play-progress").value = 0;
    return token;
  }

  function stopMusic() {
    musicToken += 1;
    if (musicVoice) {
      musicVoice.gain.gain.cancelScheduledValues(graph.context.currentTime);
      musicVoice.gain.gain.setTargetAtTime(0, graph.context.currentTime, 0.006);
      musicVoice.source.stop(graph.context.currentTime + 0.035);
      musicVoice = null;
    }
    for (const card of document.querySelectorAll(".music-card")) card.removeAttribute("data-playing");
    $("music-status").textContent = "Music stopped. Choose a track to start a loop.";
    return musicToken;
  }

  function stopPlayback() {
    stopMusic();
    return stopEffects();
  }

  async function playMusic(id) {
    errorBox.hidden = true;
    const track = musicPack?.tracks.find((item) => item.id === id);
    if (!track) throw new Error(`Unknown music track: ${id}`);
    const request = stopMusic();
    $("music-status").textContent = `Preparing ${track.title}...`;
    try {
      await audioGraph();
      if (request !== musicToken) return;
      const buffer = await bufferFor(track);
      if (request !== musicToken) return;
      const source = graph.context.createBufferSource();
      const gain = graph.context.createGain();
      source.buffer = buffer;
      source.loop = true;
      source.connect(gain).connect(graph.musicGain);
      source.onended = () => { source.disconnect(); gain.disconnect(); };
      musicVoice = { source, gain };
      const start = graph.context.currentTime + 0.03;
      gain.gain.setValueAtTime(0, start);
      gain.gain.linearRampToValueAtTime(1, start + 0.25);
      source.start(start);
      document.querySelector(`[data-music-card="${id}"]`).dataset.playing = "true";
      $("music-status").textContent = `Looping ${track.title}. Play Studio effects over this bed to compare the mix.`;
    } catch (error) {
      if (request === musicToken) {
        stopMusic();
        showError(error);
      }
    }
  }

  function updateMusicVolume() {
    const value = Number($("music-volume").value);
    if (value > 0) rememberedMusicVolume = value;
    $("music-volume-value").textContent = `${value}%`;
    $("music-mute").textContent = value === 0 ? "Unmute music" : "Mute music";
    $("music-mute").setAttribute("aria-label", value === 0 ? "Unmute music preview" : "Mute music preview");
    if (graph) graph.musicGain.gain.setTargetAtTime(value / 100, graph.context.currentTime, 0.012);
  }

  function finishMusicAdjustment() {
    if (musicAdjustmentStart !== null && Number($("music-volume").value) === 0) {
      rememberedMusicVolume = musicAdjustmentStart;
    }
    musicAdjustmentStart = null;
  }

  function nextTake(cue, style) {
    if (style === "original") {
      if (!cue.current) throw new Error(`${cue.title} has no current sound to compare.`);
      return { ...cue.current, style, label: "Previous sound / level-matched" };
    }
    const key = `${cue.id}/${style}`;
    const takes = cue.audio[style];
    const index = (counters.get(key) || 0) % takes.length;
    counters.set(key, index + 1);
    return {
      ...takes[index], style, gain: 1,
      label: `${pack.styles[style].name}${takes.length > 1 ? ` / take ${index + 1} of ${takes.length}` : ""}`,
    };
  }

  function sceneStyle(cue, setting) {
    if (setting === "hybrid") return cue.recommended;
    if (setting === "picks") {
      const decision = reviewFor(cue.id).choice;
      return approved(decision) || decision === "silence" ? decision : "studio";
    }
    return setting;
  }

  function drawTransport() {
    if (!transport) return;
    const now = graph.context.currentTime;
    const playing = transport.events.filter((event) => now >= event.start && now < event.end);
    setActiveCues(new Set(playing.map((event) => event.cue.id)));
    const label = playing.length
      ? playing.map((event) => `${event.cue.title} / ${event.take.label}`).join(" + ")
      : "A little space before the next gesture...";
    if ($("now-playing").textContent !== label) $("now-playing").textContent = label;
    $("play-progress").value = Math.max(0, Math.min(1, (now - transport.start) / (transport.end - transport.start)));
    if (now >= transport.end) {
      transport = null;
      setActiveCues(new Set());
      $("play-state").textContent = "Finished / compare the other direction";
      $("now-playing").textContent = "Choose another sound, or record your decision below.";
      $("play-progress").value = 1;
      return;
    }
    animation = requestAnimationFrame(drawTransport);
  }

  async function startEvents(events, title) {
    const request = stopEffects();
    $("play-state").textContent = "Preparing local audio";
    $("now-playing").textContent = title;
    try {
      await audioGraph();
      if (request !== token) return;
      const loaded = await Promise.all(events.map(async (event) => ({
        ...event, buffer: await bufferFor(event.take),
      })));
      if (request !== token) return;
      const base = graph.context.currentTime + 0.065;
      const scheduled = loaded.map((event) => {
        const source = graph.context.createBufferSource();
        source.buffer = event.buffer;
        const gain = graph.context.createGain();
        gain.gain.value = event.take.gain;
        source.connect(gain).connect(graph.fold);
        const voice = { source, gain };
        voices.add(voice);
        source.onended = () => {
          voices.delete(voice);
          source.disconnect();
          gain.disconnect();
        };
        const start = base + event.at;
        source.start(start);
        return { ...event, start, end: start + event.buffer.duration };
      });
      transport = { events: scheduled, start: base, end: Math.max(...scheduled.map((event) => event.end)) };
      $("play-state").textContent = title;
      animation = requestAnimationFrame(drawTransport);
    } catch (error) {
      if (request === token) {
        stopEffects();
        showError(error);
      }
    }
  }

  async function playCue(id, style) {
    errorBox.hidden = true;
    const cue = cues.get(id);
    if (!cue) throw new Error(`Unknown action: ${id}`);
    const take = nextTake(cue, style);
    await startEvents([{ cue, take, at: 0 }], `${cue.title} / ${take.label}`);
  }

  async function playScene(id, setting = $("scene-style").value) {
    errorBox.hidden = true;
    const scene = pack.scenes.find((item) => item.id === id);
    if (!scene) throw new Error(`Unknown listening scene: ${id}`);
    const events = scene.events.flatMap(([at, cueId]) => {
      const cue = cues.get(cueId);
      const style = sceneStyle(cue, setting);
      return style === "silence" ? [] : [{ at, cue, take: nextTake(cue, style) }];
    });
    if (!events.length) {
      stopEffects();
      $("now-playing").textContent = "All actions in this scene are marked Prefer silence.";
      return;
    }
    const label = setting === "hybrid" ? "Original hybrid proposal"
      : setting === "picks" ? "Your picks + Studio for pending" : pack.styles[setting].name;
    await startEvents(events, `${scene.title} / ${label}`);
  }

  function textElement(tag, text, className) {
    const element = document.createElement(tag);
    element.textContent = text;
    if (className) element.className = className;
    return element;
  }

  function waveform(cue) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 256 32");
    svg.setAttribute("preserveAspectRatio", "none");
    const style = studioApprovals.has(cue.id) ? "studio" : cue.recommended;
    const values = cue.audio[style][0].waveform;
    values.forEach((value, index) => {
      const bar = document.createElementNS(svg.namespaceURI, "rect");
      const height = Math.max(1, value * 28);
      bar.setAttribute("x", String(index * 4));
      bar.setAttribute("y", String(16 - height / 2));
      bar.setAttribute("width", "2");
      bar.setAttribute("height", String(height));
      bar.setAttribute("rx", "1");
      bar.setAttribute("fill", pack.styles[style].color);
      bar.setAttribute("opacity", "0.7");
      svg.append(bar);
    });
    return svg;
  }

  function matchesFilters(cue) {
    const mode = $("mode").value;
    if (mode === "shared" && cue.modes.length !== 2) return false;
    if (mode !== "all" && mode !== "shared" && !cue.modes.includes(mode)) return false;
    if ($("group").value !== "all" && cue.group !== $("group").value) return false;
    if ($("shortlist").checked && !cue.highlight) return false;
    const status = $("status").value;
    const choice = reviewFor(cue.id).choice;
    if (status === "approved" ? !approved(choice) : status !== "all" && choice !== status) return false;
    const query = $("search").value.trim().toLowerCase();
    return !query || [cue.id, cue.title, cue.description, cue.trigger, cue.hook, pack.groups[cue.group]]
      .join(" ").toLowerCase().includes(query);
  }

  function renderLibrary() {
    const visible = pack.cues.filter(matchesFilters);
    const grid = $("cue-grid");
    grid.replaceChildren();
    for (const cue of visible) {
      const card = $("cue-template").content.firstElementChild.cloneNode(true);
      card.dataset.cue = cue.id;
      const review = reviewFor(cue.id);
      card.dataset.decision = review.choice;
      if (activeCueIds.has(cue.id)) card.dataset.playing = "true";
      card.querySelector("h3").textContent = cue.title;
      card.querySelector(".cue-category").textContent = pack.groups[cue.group];
      card.querySelector(".cue-number").textContent = String(pack.cues.indexOf(cue) + 1).padStart(2, "0");
      const tags = card.querySelector(".cue-tags");
      tags.append(textElement("span", cue.modes.length === 2 ? "Shared" : cue.modes[0] === "classic" ? "Classic" : "Gauntlet"));
      tags.append(textElement("span", studioApprovals.has(cue.id) ? "Production / A" : "Needs approval", "suggested"));
      if (cue.optional) tags.append(textElement("span", "Optional accent", "optional"));
      if (review.previousChoice) {
        const stale = textElement("span", `Updated cue / was ${review.previousChoice}`, "optional");
        stale.dataset.stale = "true";
        tags.append(stale);
      }
      card.querySelector(".cue-description").textContent = cue.description;
      card.querySelector(".waveform").append(waveform(cue));
      for (const style of ["studio", "mythic"]) {
        const takes = cue.audio[style];
        card.querySelector(".take-meta").append(textElement("span",
          `${takes[0].duration.toFixed(2)}s / ${takes.length === 1 ? "1 take" : `${takes.length} rotating takes`}`));
        card.querySelector(`[data-style="${style}"]`).setAttribute("aria-label",
          `Play ${pack.styles[style].name}: ${cue.title}`);
        for (const [index, take] of takes.entries()) {
          const link = textElement("a", `${style === "studio" ? "A" : "B"} / take ${index + 1} WAV`);
          link.href = take.file;
          link.download = "";
          link.title = `${take.peakDb.toFixed(1)} dBFS peak / ${take.activeRmsDb.toFixed(1)} dBFS active RMS`;
          card.querySelector(".downloads").append(link);
        }
      }
      const original = card.querySelector(".original-button");
      original.disabled = !cue.current;
      original.textContent = cue.current ? "Play previous sound" : "Previously silent";
      original.setAttribute("aria-label", `Play pre-redesign comparison: ${cue.title}`);
      card.querySelector(".baseline-note").textContent = cue.current
        ? `${cue.current.name}.wav` : "New audio coverage";
      const decision = card.querySelector(".decision");
      decision.value = review.choice;
      decision.setAttribute("aria-label", `Decision: ${cue.title}`);
      card.querySelector(".decision-indicator").textContent = approved(review.choice) ? "\u2713" : "";
      const note = card.querySelector(".review-note");
      note.value = review.note;
      note.setAttribute("aria-label", `Review notes: ${cue.title}`);
      card.querySelector(".cue-trigger").textContent = cue.trigger;
      card.querySelector(".cue-hook").textContent = cue.hook;
      grid.append(card);
    }
    $("result-count").textContent = `${visible.length} of ${pack.cues.length} actions / every action has A and B`;
    $("empty").hidden = visible.length !== 0;
  }

  function renderScenes() {
    for (const scene of pack.scenes) {
      const button = document.createElement("button");
      button.className = "scene-button";
      button.dataset.scene = scene.id;
      button.append(textElement("span", "\u25b6", "scene-icon"));
      const content = document.createElement("span");
      content.append(textElement("strong", scene.title), textElement("p", scene.description));
      const length = Math.max(...scene.events.map(([at, id]) => at +
        Math.max(...Object.values(cues.get(id).audio).flat().map((take) => take.duration))));
      content.append(textElement("span", `${Math.ceil(length)} seconds / ${scene.events.length} gestures`, "scene-time"));
      button.append(content);
      $("scenes").append(button);
    }
  }

  function renderLicenses() {
    for (const option of pack.options) {
      const row = document.createElement("tr");
      const name = document.createElement("td");
      const link = textElement("a", option.name);
      link.href = option.url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      name.append(link);
      row.append(name, textElement("td", option.license), textElement("td", option.decision));
      $("option-rows").append(row);
    }
    for (const source of pack.links) {
      const link = textElement("a", source.name);
      link.href = source.url;
      if (source.url.startsWith("https:")) {
        link.target = "_blank";
        link.rel = "noopener noreferrer";
      }
      $("source-links").append(link);
    }
  }

  function renderMusic() {
    if (!musicPack || musicPack.schemaVersion !== 1 || !Array.isArray(musicPack.tracks)) {
      showError("The music catalogue is missing. Run python3 tools/generate_music.py and reload.");
      return;
    }
    for (const track of musicPack.tracks) {
      const card = document.createElement("article");
      card.className = "music-card";
      card.dataset.musicCard = track.id;
      const mode = track.mode === "classic" ? "Classic" : "Gauntlet";
      card.append(textElement("span",
        `${mode} / ~${Math.round(track.bpm)} BPM / ${track.duration.toFixed(1)}s loop${track.recommended ? " / in game" : " / alternate"}`,
        "music-meta"));
      card.append(textElement("h3", track.title), textElement("p", track.description));
      const play = textElement("button", "Play loop", "music-play");
      play.dataset.music = track.id;
      play.setAttribute("aria-label", `Play ${mode} music: ${track.title}`);
      const download = textElement("a", "Download track");
      download.href = track.file;
      download.download = "";
      card.append(play, download);
      $("music-tracks").append(card);
    }
  }

  function downloadReview() {
    const blob = new Blob([JSON.stringify(reviewDocument(), null, 2) + "\n"], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `trading-up-sound-review-${new Date().toISOString().slice(0, 10)}.json`;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
    $("storage-status").textContent = "Review export requested. Keep the JSON download to hand back your choices; exporting does not change the game.";
  }

  async function importReview(file) {
    if (file.size > 256000) throw new Error("This review is too large. Expected a sound-lab JSON file smaller than 256 KB.");
    const incoming = parseReview(JSON.parse(await file.text()));
    if ([...reviews.values()].some((item) => item.choice !== "pending" || item.note) &&
        !globalThis.confirm("Replace this browser's current decisions with the imported review? Export first if you need to keep both.")) {
      return;
    }
    reviews.clear();
    for (const [id, decision] of incoming) reviews.set(id, decision);
    errorBox.hidden = true;
    // A deliberate import is the only path allowed to replace an unreadable saved review.
    storageWritable = true;
    persistReview();
    renderLibrary();
    updateReviewCount();
    if ([...reviews.values()].some((item) => item.previousChoice)) {
      $("storage-status").textContent = "Review imported. Changed cues are pending review; previous choices and notes are retained.";
    }
  }

  async function handle(action) {
    try {
      await action();
    } catch (error) {
      showError(error);
    }
  }

  $("cue-grid").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-style]");
    if (!button) return;
    const id = button.closest("[data-cue]").dataset.cue;
    void handle(() => playCue(id, button.dataset.style));
  });
  $("cue-grid").addEventListener("change", (event) => {
    if (!event.target.matches(".decision")) return;
    const card = event.target.closest("[data-cue]");
    saveDecision(card.dataset.cue, { choice: event.target.value });
    card.dataset.decision = event.target.value;
    card.querySelector("[data-stale]")?.remove();
    card.querySelector(".decision-indicator").textContent = approved(event.target.value) ? "\u2713" : "";
    if ($("status").value !== "all") renderLibrary();
  });
  $("cue-grid").addEventListener("input", (event) => {
    if (!event.target.matches(".review-note")) return;
    saveDecision(event.target.closest("[data-cue]").dataset.cue, { note: event.target.value });
  });
  for (const id of ["search", "mode", "group", "status", "shortlist"]) {
    $(id).addEventListener(id === "search" ? "input" : "change", renderLibrary);
  }
  $("stop").addEventListener("click", stopPlayback);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") stopPlayback();
  });
  $("volume").addEventListener("input", () => {
    const value = Number($("volume").value);
    $("volume-value").textContent = `${value}%`;
    if (graph) graph.master.gain.setTargetAtTime(value / 100, graph.context.currentTime, 0.012);
  });
  $("monitor").addEventListener("change", updateMonitor);
  $("scenes").addEventListener("click", (event) => {
    const button = event.target.closest("[data-scene]");
    if (button) void handle(() => playScene(button.dataset.scene));
  });
  for (const button of document.querySelectorAll("[data-reel]")) {
    button.addEventListener("click", () => {
      $("scene-style").value = button.dataset.reel;
      void handle(() => playScene("shortlist", button.dataset.reel));
    });
  }
  $("listen-hybrid").addEventListener("click", () => {
    $("scene-style").value = "studio";
    void handle(() => playScene("shortlist", "studio"));
  });
  $("music-tracks").addEventListener("click", (event) => {
    const button = event.target.closest("[data-music]");
    if (button) void handle(() => playMusic(button.dataset.music));
  });
  $("music-stop").addEventListener("click", stopMusic);
  $("music-volume").addEventListener("input", updateMusicVolume);
  $("music-volume").addEventListener("pointerdown", () => {
    musicAdjustmentStart = rememberedMusicVolume;
  });
  $("music-volume").addEventListener("keydown", (event) => {
    if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown"].includes(event.key)) {
      musicAdjustmentStart ??= rememberedMusicVolume;
    }
  });
  for (const event of ["change", "blur", "pointercancel"]) {
    $("music-volume").addEventListener(event, finishMusicAdjustment);
  }
  $("music-mute").addEventListener("click", () => {
    finishMusicAdjustment();
    $("music-volume").value = Number($("music-volume").value) === 0 ? rememberedMusicVolume : 0;
    updateMusicVolume();
  });
  $("export").addEventListener("click", () => void handle(downloadReview));
  $("import").addEventListener("click", () => $("review-file").click());
  $("review-file").addEventListener("change", (event) => {
    const file = event.target.files[0];
    if (file) void handle(() => importReview(file));
    event.target.value = "";
  });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopPlayback();
  });
  window.addEventListener("pagehide", stopPlayback);

  const stats = [
    [pack.cues.length, "actions covered"],
    [Object.keys(pack.styles).length, "sound directions"],
    [pack.cues.reduce((sum, cue) => sum + Object.values(cue.audio).flat().length, 0), "new WAVs"],
  ];
  for (const [count, label] of stats) {
    const item = document.createElement("div");
    item.append(textElement("strong", String(count)), textElement("span", label));
    $("pack-stats").append(item);
  }
  for (const [id, name] of Object.entries(pack.groups)) {
    const option = textElement("option", name);
    option.value = id;
    $("group").append(option);
  }
  void handle(async () => {
    loadReview();
    try {
      await loadStudioApproval();
    } catch (error) {
      showError(error);
    }
    renderScenes();
    renderLibrary();
    renderMusic();
    renderLicenses();
    updateReviewCount();
  });
})();
