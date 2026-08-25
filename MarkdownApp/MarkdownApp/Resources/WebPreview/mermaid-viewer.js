(function () {
  'use strict';

  var labels = {
    open: 'Open Diagram',
    close: 'Close',
    zoomIn: 'Zoom In',
    zoomOut: 'Zoom Out',
    reset: 'Reset View'
  };
  var overlay = null;
  var stage = null;
  var canvas = null;
  var closeButton = null;
  var activeSvg = null;
  var placeholder = null;
  var originalStyle = null;
  var previousFocus = null;
  var naturalWidth = 1;
  var naturalHeight = 1;
  var fitScale = 1;
  var scale = 1;
  var panX = 0;
  var panY = 0;
  var pointers = new Map();
  var dragStart = null;
  var pinchStart = null;
  var gestureHadMultiplePointers = false;
  var tapMoved = false;
  var tapStart = null;
  var lastTap = null;

  function localizedLabels() {
    var provided = window.__markdownPreviewLabels;
    if (!provided) return;
    Object.keys(labels).forEach(function (key) {
      if (typeof provided[key] === 'string' && provided[key]) labels[key] = provided[key];
    });
  }

  function button(glyph, label, action) {
    var element = document.createElement('button');
    element.type = 'button';
    element.className = 'mermaid-viewer__button';
    element.textContent = glyph;
    element.setAttribute('aria-label', label);
    element.addEventListener('click', function (event) {
      event.stopPropagation();
      action();
    });
    return element;
  }

  function ensureViewer() {
    if (overlay) return;
    localizedLabels();

    overlay = document.createElement('div');
    overlay.className = 'mermaid-viewer';
    overlay.hidden = true;
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', labels.open);

    stage = document.createElement('div');
    stage.className = 'mermaid-viewer__stage';
    stage.setAttribute('tabindex', '-1');

    canvas = document.createElement('div');
    canvas.className = 'mermaid-viewer__canvas';
    stage.appendChild(canvas);

    var toolbar = document.createElement('div');
    toolbar.className = 'mermaid-viewer__toolbar';
    toolbar.setAttribute('role', 'toolbar');

    toolbar.appendChild(button('−', labels.zoomOut, function () { zoomBy(0.8); }));
    toolbar.appendChild(button('+', labels.zoomIn, function () { zoomBy(1.25); }));
    toolbar.appendChild(button('↺', labels.reset, resetView));
    closeButton = button('×', labels.close, close);
    closeButton.classList.add('mermaid-viewer__button--close');
    toolbar.appendChild(closeButton);

    overlay.appendChild(stage);
    overlay.appendChild(toolbar);
    document.body.appendChild(overlay);

    stage.addEventListener('pointerdown', pointerDown);
    stage.addEventListener('pointermove', pointerMove);
    stage.addEventListener('pointerup', pointerUp);
    stage.addEventListener('pointercancel', pointerUp);
    stage.addEventListener('wheel', wheel, { passive: false });
    overlay.addEventListener('keydown', keyDown);
    window.addEventListener('resize', function () {
      if (!overlay.hidden) resetView();
    });
  }

  function dimensions(svg) {
    var viewBox = svg.viewBox && svg.viewBox.baseVal;
    if (viewBox && viewBox.width > 0 && viewBox.height > 0) {
      return { width: viewBox.width, height: viewBox.height };
    }
    var bounds = svg.getBoundingClientRect();
    return {
      width: Math.max(bounds.width, 1),
      height: Math.max(bounds.height, 1)
    };
  }

  function open(host, focusToolbar) {
    var svg = host && host.querySelector('svg');
    if (!svg) return;
    ensureViewer();
    if (activeSvg) close();

    activeSvg = svg;
    lastTap = null;
    previousFocus = document.activeElement;
    originalStyle = svg.getAttribute('style');
    var size = dimensions(svg);
    naturalWidth = size.width;
    naturalHeight = size.height;

    placeholder = document.createElement('div');
    placeholder.className = 'mermaid-viewer__placeholder';
    placeholder.style.height = Math.ceil(svg.getBoundingClientRect().height) + 'px';
    svg.replaceWith(placeholder);

    canvas.replaceChildren(svg);
    canvas.style.width = naturalWidth + 'px';
    canvas.style.height = naturalHeight + 'px';
    svg.style.width = '100%';
    svg.style.height = '100%';
    svg.style.maxWidth = 'none';

    document.getElementById('content').inert = true;
    document.body.classList.add('mermaid-viewer-open');
    overlay.hidden = false;
    requestAnimationFrame(function () {
      resetView();
      if (focusToolbar) closeButton.focus();
      else stage.focus({ preventScroll: true });
    });
  }

  function close() {
    if (!activeSvg) return;
    pointers.clear();
    if (placeholder && placeholder.parentNode) placeholder.replaceWith(activeSvg);
    if (originalStyle === null) activeSvg.removeAttribute('style');
    else activeSvg.setAttribute('style', originalStyle);

    overlay.hidden = true;
    document.body.classList.remove('mermaid-viewer-open');
    var content = document.getElementById('content');
    if (content) content.inert = false;

    activeSvg = null;
    placeholder = null;
    lastTap = null;
    canvas.replaceChildren();
    if (previousFocus && previousFocus.isConnected) previousFocus.focus();
    previousFocus = null;
  }

  function resetView() {
    if (!activeSvg) return;
    var bounds = stage.getBoundingClientRect();
    var availableWidth = Math.max(bounds.width - 32, 1);
    var availableHeight = Math.max(bounds.height - 32, 1);
    fitScale = Math.min(availableWidth / naturalWidth, availableHeight / naturalHeight, 1);
    scale = fitScale;
    panX = 0;
    panY = 0;
    applyTransform();
  }

  function scaleRange() {
    return {
      minimum: Math.max(Math.min(fitScale * 0.5, 0.1), 0.02),
      maximum: Math.max(4, fitScale * 12)
    };
  }

  function clampedScale(value) {
    var range = scaleRange();
    return Math.min(Math.max(value, range.minimum), range.maximum);
  }

  function constrainPan() {
    var bounds = stage.getBoundingClientRect();
    var maxX = Math.max(0, (naturalWidth * scale - bounds.width) / 2 + 48);
    var maxY = Math.max(0, (naturalHeight * scale - bounds.height) / 2 + 48);
    panX = Math.min(Math.max(panX, -maxX), maxX);
    panY = Math.min(Math.max(panY, -maxY), maxY);
  }

  function applyTransform() {
    constrainPan();
    canvas.style.transform =
      'translate3d(calc(-50% + ' + panX + 'px), calc(-50% + ' + panY + 'px), 0) scale(' + scale + ')';
  }

  function zoomTo(value, clientX, clientY) {
    var next = clampedScale(value);
    if (Math.abs(next - scale) < 0.0001) return;
    var bounds = stage.getBoundingClientRect();
    var focusX = typeof clientX === 'number' ? clientX - bounds.left - bounds.width / 2 : 0;
    var focusY = typeof clientY === 'number' ? clientY - bounds.top - bounds.height / 2 : 0;
    var ratio = next / scale;
    panX = focusX - (focusX - panX) * ratio;
    panY = focusY - (focusY - panY) * ratio;
    scale = next;
    applyTransform();
  }

  function zoomBy(factor) {
    zoomTo(scale * factor);
  }

  function midpoint(values) {
    return {
      x: (values[0].x + values[1].x) / 2,
      y: (values[0].y + values[1].y) / 2
    };
  }

  function distance(values) {
    return Math.hypot(values[0].x - values[1].x, values[0].y - values[1].y);
  }

  function beginPinch() {
    var values = Array.from(pointers.values()).slice(0, 2);
    var middle = midpoint(values);
    var bounds = stage.getBoundingClientRect();
    pinchStart = {
      distance: Math.max(distance(values), 1),
      scale: scale,
      anchorX: (middle.x - bounds.left - bounds.width / 2 - panX) / scale,
      anchorY: (middle.y - bounds.top - bounds.height / 2 - panY) / scale
    };
  }

  function pointerDown(event) {
    event.preventDefault();
    stage.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.size === 1) {
      dragStart = { x: event.clientX, y: event.clientY, panX: panX, panY: panY };
      tapStart = { x: event.clientX, y: event.clientY };
      tapMoved = false;
      gestureHadMultiplePointers = false;
    } else {
      gestureHadMultiplePointers = true;
      beginPinch();
    }
  }

  function pointerMove(event) {
    if (!pointers.has(event.pointerId)) return;
    event.preventDefault();
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (tapStart && Math.hypot(event.clientX - tapStart.x, event.clientY - tapStart.y) > 8) {
      tapMoved = true;
    }

    if (pointers.size >= 2 && pinchStart) {
      var values = Array.from(pointers.values()).slice(0, 2);
      var middle = midpoint(values);
      var bounds = stage.getBoundingClientRect();
      scale = clampedScale(pinchStart.scale * distance(values) / pinchStart.distance);
      panX = middle.x - bounds.left - bounds.width / 2 - pinchStart.anchorX * scale;
      panY = middle.y - bounds.top - bounds.height / 2 - pinchStart.anchorY * scale;
      applyTransform();
      return;
    }

    if (pointers.size === 1 && dragStart) {
      panX = dragStart.panX + event.clientX - dragStart.x;
      panY = dragStart.panY + event.clientY - dragStart.y;
      applyTransform();
    }
  }

  function pointerUp(event) {
    if (!pointers.has(event.pointerId)) return;
    var wasTap = pointers.size === 1 && !tapMoved && !gestureHadMultiplePointers;
    pointers.delete(event.pointerId);

    if (wasTap) {
      var now = Date.now();
      if (lastTap && now - lastTap.time < 320 &&
          Math.hypot(event.clientX - lastTap.x, event.clientY - lastTap.y) < 32) {
        if (scale > fitScale * 1.1) resetView();
        else zoomTo(Math.max(1, fitScale * 2.5), event.clientX, event.clientY);
        lastTap = null;
      } else {
        lastTap = { time: now, x: event.clientX, y: event.clientY };
      }
    }

    pinchStart = null;
    if (pointers.size === 1) {
      var remaining = Array.from(pointers.values())[0];
      dragStart = { x: remaining.x, y: remaining.y, panX: panX, panY: panY };
    } else {
      dragStart = null;
      tapStart = null;
      gestureHadMultiplePointers = false;
    }
  }

  function wheel(event) {
    event.preventDefault();
    zoomTo(scale * Math.exp(-event.deltaY * 0.002), event.clientX, event.clientY);
  }

  function keyDown(event) {
    if (event.key === 'Escape') close();
    else if (event.key === '+' || event.key === '=') zoomBy(1.25);
    else if (event.key === '-') zoomBy(0.8);
    else if (event.key === '0') resetView();
    else if (event.key === 'Tab') {
      var controls = Array.from(overlay.querySelectorAll('button'));
      var index = controls.indexOf(document.activeElement);
      var next = event.shiftKey ? index - 1 : index + 1;
      if (next < 0) next = controls.length - 1;
      if (next >= controls.length) next = 0;
      event.preventDefault();
      controls[next].focus();
    } else return;
    event.preventDefault();
  }

  function enhance(hosts) {
    localizedLabels();
    Array.from(hosts || []).forEach(function (host) {
      if (!host.querySelector('svg') || host.dataset.viewerEnhanced === 'true') return;
      host.dataset.viewerEnhanced = 'true';
      host.classList.add('mermaid--viewable');
      host.setAttribute('role', 'button');
      host.setAttribute('tabindex', '0');
      host.setAttribute('aria-label', labels.open);
      host.addEventListener('click', function () { open(host, false); });
      host.addEventListener('keydown', function (event) {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        open(host, true);
      });
    });
  }

  window.MermaidViewer = {
    enhance: enhance,
    close: close
  };
})();
