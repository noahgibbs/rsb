class SimpleBenchController < ApplicationController
  def static
    render :text => "Static Text"
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
end
