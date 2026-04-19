class ApplicationController < RageController::API
  def redirect_to(location)
    headers["location"] = location
    head 302
  end
end
