// SPDX-License-Identifier: GPL-3.0-or-later
//
// Simplified Chinese UI localisation for the Netdata dashboard.
//
// The dashboard shipped with the Agent is a prebuilt, closed-source React SPA that contains no
// internationalisation layer of its own. This script therefore translates the rendered DOM in the
// browser: exact matches from zh-CN.json are substituted into text nodes and into a small set of
// user-visible attributes.
//
// Only strings present in the dictionary are ever touched, so any wording the dictionary does not
// know is left exactly as the dashboard rendered it. A missing, unreadable or malformed dictionary
// degrades to an untranslated (English) dashboard instead of breaking the page.
(function () {
  'use strict';

  if (window.__netdataZhCnLoaded) return;
  window.__netdataZhCnLoaded = true;

  var ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];
  var dictionary = null;

  // Resolve the directory this script was served from, so the dictionary is found in an agent
  // served under a sub-path just as well as one served from the root.
  var baseUrl = (function () {
    var current = document.currentScript;
    if (current && current.src) return current.src.replace(/[^/]*$/, '');
    return '/v3/';
  })();

  function substitute(value) {
    if (!value) return null;
    var trimmed = value.trim();
    if (!trimmed) return null;
    var translated = dictionary[trimmed];
    if (!translated) return null;
    // Use a function replacement so that '$' in a translation is never treated as a backreference.
    return value.replace(trimmed, function () { return translated; });
  }

  function translateTextNode(node) {
    var replaced = substitute(node.nodeValue);
    if (replaced === null || replaced === node.nodeValue) return false;
    node.nodeValue = replaced;
    return true;
  }

  function translateAttributes(element) {
    for (var i = 0; i < ATTRS.length; i++) {
      var name = ATTRS[i];
      var current = element.getAttribute(name);
      if (!current) continue;
      var replaced = substitute(current);
      if (replaced === null) continue;
      element.setAttribute(name, replaced);
    }
  }

  function translateSubtree(element) {
    if (!element || element.nodeType !== 1) return;

    translateAttributes(element);

    var walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, null);
    var node;
    while ((node = walker.nextNode())) {
      if (node.nodeType === 3) translateTextNode(node);
      else translateAttributes(node);
    }
  }

  // React re-renders constantly, so mutations are queued and applied once per frame rather than
  // translating on every individual mutation record.
  var pending = new Set();
  var scheduled = false;

  function flush() {
    scheduled = false;
    var roots = pending;
    pending = new Set();
    roots.forEach(translateSubtree);
  }

  function schedule(node) {
    if (!node) return;
    var target = node.nodeType === 3 ? node.parentNode : node;
    if (!target) return;
    pending.add(target);
    if (scheduled) return;
    scheduled = true;
    if (window.requestAnimationFrame) window.requestAnimationFrame(flush);
    else setTimeout(flush, 16);
  }

  var observer = new MutationObserver(function (records) {
    for (var i = 0; i < records.length; i++) {
      var record = records[i];
      if (record.type === 'characterData') {
        schedule(record.target);
        continue;
      }
      if (record.type === 'attributes') {
        schedule(record.target);
        continue;
      }
      for (var j = 0; j < record.addedNodes.length; j++) {
        var added = record.addedNodes[j];
        if (added.nodeType === 1 || added.nodeType === 3) schedule(added);
      }
    }
  });

  function start() {
    translateSubtree(document.body || document.documentElement);
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: ATTRS
    });
  }

  // The dictionary is revalidated on every page load. It is small, and an administrator who has just
  // re-applied the patch must see the new wording without having to bypass the browser cache that the
  // Agent sets for the rest of the dashboard bundle.
  fetch(baseUrl + 'zh-CN.json', { cache: 'no-cache' })
    .then(function (response) {
      if (!response.ok) throw new Error('zh-CN.json: HTTP ' + response.status);
      return response.json();
    })
    .then(function (data) {
      if (!data || typeof data !== 'object') throw new Error('zh-CN.json: not an object');
      dictionary = data;
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
      } else {
        start();
      }
    })
    .catch(function (error) {
      // Untranslated is an acceptable outcome; a broken dashboard is not.
      console.warn('[zh-CN] dashboard localisation disabled:', error && error.message);
    });
})();
