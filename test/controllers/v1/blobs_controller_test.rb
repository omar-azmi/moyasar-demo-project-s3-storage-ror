require "test_helper"

class V1::BlobsControllerTest < ActionDispatch::IntegrationTest
  # test "the truth" do
  #   assert true
  # end

  # Setup method to initialize any shared variables (e.g., test payloads)
  def setup
    @valid_id = "test_blob7"
    @valid_payload = {
      id: @valid_id,
      data: Base64.strict_encode64("Hello, world!")
    }.to_json
    @invalid_payload = { foo: "bar" }.to_json
  end

  # Test valid POST request
  test "should create blob with valid payload" do
    post("/v1/blobs", params: @valid_payload, headers: { "Content-Type": "application/json", "Authorization": "Bearer my-secret-token"  })
    assert_response :created
    assert_includes @response.body, "Blob stored successfully"
  end

  # Test invalid POST request
  test "should return unprocessable_entity with invalid payload" do
    post("/v1/blobs", params: @invalid_payload, headers: { "Content-Type": "application/json" })
    assert_response :unprocessable_entity
    assert_includes @response.body, "Incorrect json body provided"
  end

  test "should get blob by id" do
    get("/v1/blobs/#{@valid_id}", headers: { "Authorization": "Bearer my-secret-token" })
    assert_response :ok
    assert_match "Hello, world!", Base64.strict_decode64(JSON.parse(@response.body)["data"])
  end

  test "should return not_found for non-existing blob" do
    get("/v1/blobs/#{"non_existing_blob"}", headers: { "Authorization": "Bearer some-token" })
    assert_response :not_found
    assert_includes @response.body, "Object not found"
  end
end
