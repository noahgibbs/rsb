-- example dynamic request script which demonstrates changing
-- the request path and a header for each request
-------------------------------------------------------------
-- NOTE: each wrk thread has an independent Lua scripting
-- context and thus there will be one counter per thread

counter = 0
urls = {}

init = function()
  urls[1] = wrk.format(nil, "/mandelbrot?x=0.1&i=0.7")
  urls[2] = wrk.format(nil, "/mandelbrot?x=1.0&i=-0.3")
  urls[3] = wrk.format(nil, "/mandelbrot?x=-0.4&i=-0.4")
  urls[4] = wrk.format(nil, "/mandelbrot?x=2.7&i=0.0")
  urls[5] = wrk.format(nil, "/mandelbrot?x=0.2&i=-0.95")
end

request = function()
   local index = math.random(1, 5)
   return urls[index]
end
