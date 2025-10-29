require "test_helper"

class Api::V1::TextractControllerTest < ActionDispatch::IntegrationTest
  test "should get upload" do
    get api_v1_textract_upload_url
    assert_response :success
  end
end
