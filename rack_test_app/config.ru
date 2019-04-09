require "complex"
require "rack"

class SpeedTest
  ROUTES = {
    "/" => proc { [200, {"Content-Type" => "text/html"}, ["Hello World!"]] },
    "/static" => proc { [200, {"Content-Type" => "text/html"}, ["Static Text"]] },
    "/request" => proc { |env| r = Rack::Request.new(env); [200, {"Content-Type" => "text/html"}, ["Static Text"]] },
    "/mandelbrot" => proc { |env|
      x, i = env["QUERY_STRING"].split("&",2).map { |item| item.split("=", 2)[1].to_f }

      [200, {"Content-Type" => "text/html"}, [ SpeedTest.in_mandelbrot(x,i) ? "in" : "out" ]]
    },
    "/fivehundred" => proc { raise "This raises an error!" },
    "/delay" => proc { |env|
      t = 0.001
      if env["QUERY_STRING"] != nil && env["QUERY_STRING"] != ""
        t = env["QUERY_STRING"].split("=",2)[1].to_f
      end
      sleep t
      [ 200, { "Content-Type" => "text/html" }, [ "Static Text" ] ]
    },
    # Not yet: /db
    "/shutdown" => proc { exit 0 },
  }

  def self.in_mandelbrot(x, i)
    z0 = Complex(x, i)
    z = z0
    80.times { z = z * z }
    z.abs < 2.0
  end

  def call(env)
    route = ROUTES[env["PATH_INFO"]]
    if route
      return route.call(env)
    else
      [ 404, { "Content-Type" => "text/html" }, [ "Sad Trombone... Your route is not found." ] ]
    end
  end
end

run SpeedTest.new
