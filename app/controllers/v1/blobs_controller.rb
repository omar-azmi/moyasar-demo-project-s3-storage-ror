require "json"


class V1::BlobsController < ActionController::API
  # attr_accessor :params # inherited from `ActionController::API`, and it shows the current parameters of the request's url
  # attr_accessor :request # inherited from `ActionController::API`, and it represents the http request details

  # method for storing a user's blob
  def create
    headers = request.headers # .to_h().transform_keys(&:downcase) # no need to transform, th header object is key-casing insensitive
    # Extract the "Authorization" header key composite ID value from URL parameters.
    # @type [nil, String]
    bearer = self.parse_bearer(headers)
    # HTTP codes corresponding to each rails symbol can be seen here: "https://apidock.com/rails/ActionController/Base/render#254-List-of-status-codes-and-their-symbols"
    content_type_header = headers["content-type"]
    unless content_type_header.nil? || content_type_header.strip().empty? || content_type_header.strip().downcase() == "application/json"
      render(json: { error: "Endpoint only accepts \"application/json\" as the mime type" }, status: :unsupported_media_type)
      return
    end
    # the user's payload
    payload = JSON.parse(request.body.read) rescue nil
    if payload.nil? || (not payload["id"].is_a?(String)) || (not payload["data"].is_a?(String))
      render(json: { error: "Incorrect json body provided" }, status: :unprocessable_entity)
      return
    end

    backend_index = -1
    begin
      # Writing the blob by accessing the frontend socket
      backend_index = STORAGE_FRONTEND_SOCKET.write_object(payload, bearer: bearer).wait
    rescue => error
      render(json: { error: error.message }, status: :unprocessable_entity)
    else
      if backend_index >= 0
        render(json: { message: "Blob stored successfully" }, status: :created)
      else
        render(json: { error: "Storage is unavailable" }, status: :service_unavailable)
      end
    end
  end

  # method for retrieve a user's blob by id
  def show
    id = params[:id]
    bearer = self.parse_bearer(request.headers)

    begin
      # Read the blob by accessing the frontend socket
      # @type [nil, StorageObjectReadJson]
      blob = STORAGE_FRONTEND_SOCKET.read_object(id, bearer: bearer).wait
    rescue => error
      render(json: { error: error.message }, status: :unauthorized)
    else
      unless blob.nil?
        render(json: blob.to_h(), status: :ok)
      else
        render(json: { error: "Object not found, or storage is down" }, status: :not_found)
      end
    end
  end

  private def parse_bearer(headers)
    # @type [nil, String]
    auth = headers["authorization"]
    auth.nil? \
      ? nil
      : auth.strip().start_with?("Bearer") \
        ? auth.strip().gsub("Bearer", "").strip()
        : nil
  end
end
