/* Native callers pass JSON strings and key labels through WebKit arguments. */
(() => {
  const context = document.querySelector('canvas').getContext('2d');
  const renderer = KuroRenderer;
  const classic = { formatVersion: 1, name: 'KuroCat', palette: { body: '#161618', whiskers: '#E0E6EBAD', crease: '#D1EBE3C2' }, idleLegs: 'chest' };
  const keys = new Map(renderer.KEYCAPS.map(cap => [cap.legend === 'space' ? 'SPACE' : cap.legend, cap]));
  let skin, state, theme, lastTime = 0, motionStart = 0, activity = 'resting';
  let running = false, frame = 0, queue = [], nextKey = 0, loadRevision = 0;
  let drag = null;

  function draw() {
    renderer.drawScene(context, skin, state, { kbTheme: theme, whiteOutline: true });
  }

  function animate(now) {
    if (!running || !skin) return;
    const dt = Math.min(0.05, (now - (lastTime || now)) / 1000);
    const elapsed = (now - motionStart) / 1000;
    lastTime = now;
    state.time += dt;
    if (!drag && now >= nextKey && queue.length) {
      renderer.triggerKeyTap(state, skin, queue.shift());
      nextKey = now + 85;
    }
    const phase = state.time % 4;
    state.blinkProgress = Math.max(0, 1 - Math.abs(phase - 3) / 0.12);
    state.headYaw = activity === 'searching' ? Math.sin(elapsed * 5) * 0.4 : Math.sin(elapsed * 2) * 0.12;
    state.eyeGazeX = state.headYaw;
    const lap = activity === 'playing' ? elapsed % 1.2 : Math.min(elapsed, 0.85);
    state.headOffsetY = ['celebrating', 'playing'].includes(activity) ? -16 * Math.sin(Math.PI * Math.min(1, lap / 0.85)) : 0;
    const damping = Math.exp(-dt * 8);
    state.dragSwingTarget *= damping;
    state.dragSwingYTarget *= damping;
    renderer.stepPhysicsExtras(state, skin, drag ? 'drag' : 'idle', dt);
    draw();
    frame = requestAnimationFrame(animate);
  }

  window.configurePet = async (skinJSON, keyboardJSON) => {
    const revision = ++loadRevision;
    cancelAnimationFrame(frame);
    const raw = skinJSON ? JSON.parse(skinJSON) : classic;
    if (['beagle', 'damiao', 'naimi'].includes(raw.renderStyle)) return 'artwork';
    if (!KuroSpec.validateRawSkin(raw).ok) return 'invalid';
    if ((raw.decorations || []).some(deco => !/^(?:data:image\/png;base64,)?[A-Za-z0-9+/=]+$/.test(deco.png))) return 'invalid';
    const resolved = KuroSpec.resolveSkin(raw);
    await renderer.preloadDecorations(resolved.decorations);
    if (revision !== loadRevision) return 'invalid';
    skin = resolved;
    theme = 'classicMilk';
    if (keyboardJSON) {
      theme = 'pocketWorkshop';
      renderer.registerKeyboardTheme(theme, JSON.parse(keyboardJSON).colors);
    }
    state = renderer.createDefaultState();
    drag = null;
    queue = [];
    nextKey = 0;
    lastTime = 0;
    draw();
    if (running) frame = requestAnimationFrame(animate);
    return 'ok';
  };

  window.updatePet = (newActivity, keyLabels, animatePet, dragPosition = null) => {
    if (!skin) return;
    if (dragPosition) {
      if (drag) {
        if (drag.x !== dragPosition.x) {
          state.dragSwingTarget = Math.max(-0.92, Math.min(0.92, (drag.x - dragPosition.x) * 5));
        }
        if (drag.y !== dragPosition.y) {
          state.dragSwingYTarget = Math.max(-0.78, Math.min(0.78, (drag.y - dragPosition.y) * 4));
        }
      } else {
        queue = [];
        state.dragSwingTarget = 0;
        state.dragSwingYTarget = 0;
        state.scruffDrag = 1;
      }
    }
    drag = dragPosition;
    if (newActivity !== activity) {
      activity = newActivity;
      motionStart = performance.now();
    }
    if (!drag) queue = queue.concat(keyLabels.map(label => keys.get(label)).filter(Boolean)).slice(-64);
    if (animatePet) {
      if (!running) {
        lastTime = 0;
        frame = requestAnimationFrame(animate);
      }
      if (drag && !state.isScruffDragging) {
        renderer.stepPhysicsExtras(state, skin, 'drag', 0.001);
        draw();
      }
    } else {
      cancelAnimationFrame(frame);
      queue = [];
      state = renderer.createDefaultState();
      if (drag) {
        state.scruffDrag = 1;
        renderer.stepPhysicsExtras(state, skin, 'drag', 0.001);
      }
      draw();
    }
    running = animatePet;
  };

  window.petThumbnail = () => context.canvas.toDataURL('image/png').split(',')[1];
})();
