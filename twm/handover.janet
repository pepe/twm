(import spork/json)

(def javascript
  "Browser-side readiness waiter. A new transition cancels the preceding one."
  ``
window.mtbAwaitPlace = async function (address, role, done) {
  const ticket = window.mtbHandover = (window.mtbHandover || 0) + 1;
  const url = new URL(address || '/', location.href);
  url.pathname = url.pathname.replace(/\/?$/, '/') + '_ready';
  url.search = '';
  const deadline = Date.now() + 30000;
  while (ticket === window.mtbHandover && Date.now() < deadline) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 1000);
    try {
      const response = await fetch(url, {cache: 'no-store', signal: controller.signal});
      const state = response.ok && await response.json();
      if (state && state.ready && state.generation && (!role || state.role === role)) {
        if (ticket === window.mtbHandover) done();
        return;
      }
    } catch (_) {
      // Refusal during a listener handover is expected; it is not readiness.
    } finally {
      clearTimeout(timeout);
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  if (ticket !== window.mtbHandover) return;
  const stage = document.getElementById('stage') || document.body;
  const message = document.createElement('p');
  message.textContent = 'This place is not ready yet. Your page has been kept.';
  const retry = document.createElement('button');
  retry.textContent = 'Try again';
  retry.onclick = () => { message.remove(); retry.remove(); window.mtbAwaitPlace(address, role, done); };
  stage.append(message, retry);
};
``)

(defn wait-script
  "Returns a readiness-triggered transition, preserving the existing document."
  [address role after]
  (string javascript "\nwindow.mtbAwaitPlace(" (json/encode (or address "/")) ","
          (json/encode role) ",function(){" after "});"))
