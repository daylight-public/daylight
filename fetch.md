### fetch

fetch was created to replace XMLHttpRequest, and early and widely-used browser-based method for getting data from other URLs. If you wrote a simple Web page that grabbed sports scores, stock prices, weather data, or any information at all, you probably used XmlHttpRequest.

XHR got old.
And along the way, someone had an interesting insight: calling a URL and getting back a resource is useful in the browser, but it's useful on the server-side as well. For example, building an HTTP framework or microframework. After all, taking URLs and returning resources is pretty much what an HTTP framework does. Why not use an XHR replacement for that as well? That way the same tool is used in the browser and on the server. That's always good.

So an industry consortium called WHATWG decided to take this on.
And fetch() was born.

### Early days

WHATWG anounced fetch() with the support of the Node organization, and the expectation that Node would release an implementation of fetch().
Only two things happened:

- The node module took 3 years
- It didn't faithfully implement the WHATWG standard.

So the WHATWG team decided to build their own node implementation instead. And so, 2 competing implementations existed
- `fetch`, created by the Node team, that was natively part of Node but not a 100% impl of WHATWG fetch()
- `node-fetch`, created by WHATWG, that *was* 100% compatible with WHATWG fetch().

### node !== JavaScript

Releasing a 100%-compliant node module didn't end the mission. It only solved it on the server side. Browsers don't run node, browsers don't use Node modules, and so browsers needed WHATWG fetch() love too. Some popular attempts have emerged

https://www.npmjs.com/package/whatwg-fetch - A polyfill by Jake Champion that implements a subset of WHATWG fetch(), focusing on implementing as much of fetch() to replace XHR across as many browsers as possible. Based on stars (25K+) and forks (3K+), this looks widely adopted. **Only works in the browser**

https://github.com/matthew-andrews/isomorphic-fetch - A library built on top of both whatwg-fetch for the browers, and node-fetch() on the server side. In other words isomorphic-fetch is an attempt at One Fetch to Rule Them All, on both browser and server.

https://github.com/lquixada/cross-fetch - An alternative to isomorphic fetch

https://github.com/developit/unfetch - A minimal isomorphic-fetch knockoff?

### But wait there's more

https://github.com/ardatan/whatwg-node appears to be a project by an individual. It consists of a few projects, including ...

- server, a library to allow creating servers for any runtime, eg Node, Cloudflare, Lambda, etc

- fetch, used by server to allow for the cross-platform bit.

It's a bit confusing to see packages named whatwg-node/server and whatwg-node/fetch, released by someone who appararently has no affiliation with WHATWG, and so these packages are not actually part of WHATWG at all. But it looks like that's how it is. It's just a confusing name or names.

Incidentally this package seems lightly adopted. 300+ stars is nothing to sneeze at but it's substantially less adoption than the other packages above.





