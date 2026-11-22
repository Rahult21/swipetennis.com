import api from './worker.mjs';

// The existing Git-connected Worker serves the website and the native app's JSON API.
export default {
  fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/api/')) {
      url.pathname = url.pathname.slice(4);
      return api.fetch(new Request(url, request), env, ctx);
    }
    return env.ASSETS.fetch(request);
  }
};
