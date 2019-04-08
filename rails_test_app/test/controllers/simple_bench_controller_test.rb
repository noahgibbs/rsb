require 'test_helper'

class SimpleBenchControllerTest < ActionController::TestCase
  test "should get static" do
    get :static
    assert_response :success
  end

  test "should get db" do
    get :db
    assert_response :success
  end

  #test "should get fivehundred" do
  #  get :fivehundred
  #  assert_response 500
  #end

  test "should get delay with no param" do
    get :delay
    assert_response :success
  end

  test "should get delay with param" do
    get :delay, time: "0.03"
    assert_response :success
  end

end
