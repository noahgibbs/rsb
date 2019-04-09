class SimpleBenchController < ApplicationController
  def static
    render :text => "Static Text"
  end

  def mandelbrot
    z0 = Complex(params["x"].to_f, params["i"].to_f)
    z = z0
    80.times { z = z * z0 }
    render :text => (z.abs <= 2.0 ? "in" : "out")
  end

  def db
    # TBD
    render :text => "For now, static"
  end

  def fivehundred
    raise "This gives an error!"
  end

  def delay
    t = params[:time].to_f || 0.001
    sleep t
    render :text => "Static Text"
  end

  # Keep in mind that this route only does what you think for single-process setups,
  # not anything with workers and a master process.
  def shutdown
    exit 0
  end
end
