/**
 * Redmine - project management software
 * Copyright (C) 2006-  Jean-Philippe Lang
 * This code is released under the GNU General Public License.
 */
import { Controller } from "@hotwired/stimulus"

let mermaidInitialized = false;
let mermaidLoadPromise = null;

// mermaid.js is several MB, so it must not be part of every page's baseline
// load. It is only fetched (as a classic <script>, via the URL exposed as
// window.MermaidAssetUrl by javascript_heads) once a ```mermaid code block
// actually needs rendering.
function loadMermaid() {
  if (typeof mermaid !== 'undefined') return Promise.resolve(mermaid);
  if (mermaidLoadPromise) return mermaidLoadPromise;
  if (!window.MermaidAssetUrl) return Promise.reject(new Error('MermaidAssetUrl is not set'));

  const loading = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = window.MermaidAssetUrl;
    script.onload = () => {
      if (window.mermaid) {
        resolve(window.mermaid);
      } else {
        script.remove();
        reject(new Error('mermaid.js loaded but window.mermaid is not defined'));
      }
    };
    script.onerror = () => {
      script.remove();
      reject(new Error('Failed to load mermaid.js'));
    };
    document.head.appendChild(script);
  });
  // Keeping a rejected promise around would stop every later connect() in the
  // same page -- another block, or a repeated preview -- from trying again.
  loading.catch(() => {
    if (mermaidLoadPromise === loading) mermaidLoadPromise = null;
  });
  mermaidLoadPromise = loading;
  return loading;
}

// Connects to data-controller="mermaid"
// Renders ```mermaid code blocks (marked with this controller by
// Redmine::WikiFormatting::SyntaxHighlight#process) as diagrams.
export default class extends Controller {
  connect() {
    loadMermaid().then((mermaid) => {
      this.render(mermaid);
    }).catch((error) => {
      console.error('Failed to load mermaid.js:', error);
    });
  }

  render(mermaid) {
    if (!mermaidInitialized) {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });
      mermaidInitialized = true;
    }

    const pre = this.element.closest('pre');
    const container = document.createElement('div');
    container.className = 'mermaid';
    container.textContent = this.element.textContent.trim();
    (pre || this.element).insertAdjacentElement('afterend', container);

    // mermaid.js draws its own error diagram on failure
    // replace it with a redmine flash message while keeping the source block available
    // so the invalid diagram can be inspected and copied
    mermaid.run({ nodes: [container], suppressErrors: false }).then(() => {
      if (pre) pre.style.display = 'none';
    }).catch((error) => {
      container.remove();

      const errorElement = document.createElement('div');
      errorElement.className = 'flash error';
      errorElement.innerHTML = '<p>Failed to render mermaid diagram:</p>';

      const message = document.createElement('p');
      message.textContent = error?.message || String(error);

      errorElement.appendChild(message);

      const wrapper = pre.closest('.pre-wrapper');
      if (wrapper) {
        wrapper.insertAdjacentElement('beforebegin', errorElement);
      }
    });
  }
}
