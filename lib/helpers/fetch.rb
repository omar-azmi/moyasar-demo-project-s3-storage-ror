require "net/http"
require "uri"
require "async"
require_relative "./async_promise"

# Synchronous http javascript-like fetch function
# @param url [String] the url to fetch from (including http uri schema)
# @param method [String] the http method to use
# @param headers [Hash<String, String>] additional headers to add to your request
# @param body [String] optional body to include in your request
# @param timeout [Float] specify how long to wait before timeout in seconds
def fetch(url, method: "GET", headers: {}, body: nil, timeout: 60)
  uri = URI.parse(url)
  response = nil
  Net::HTTP.start(uri.host, uri.port, open_timeout: timeout, read_timeout: timeout) do |http|
    request = build_http_request(uri, method, headers, body)
    response = http.request(request)
  end
  response
end

# Asynchronous (AsyncPromise) http javascript-like fetch function
# @param url [String] the url to fetch from (including http uri schema)
# @param method [String] the http method to use
# @param headers [Hash<String, String>] additional headers to add to your request
# @param body [String] optional body to include in your request
# @param timeout [Float] specify how long to wait before timeout in seconds
def async_fetch(url, method: "GET", headers: {}, body: nil, timeout: 60)
  promise = AsyncPromise.resolve().then(->(_) {
    fetch(url, method: method, headers: headers, body: body, timeout: timeout)
  })
end

# use `URI::Parser.new().escape` to perform url-escaping of any weird characters
def escape_url_component(url_component)
  URI::Parser.new().escape(url_component)
end

# Helper function to build http requests of various http-methods, and also assign headers
def build_http_request(uri, method, headers, body)
  request = nil
  case method.upcase()
  when "GET"
    request = Net::HTTP::Get.new(uri)
  when "HEAD"
    request = Net::HTTP::Head.new(uri)
  when "DELETE"
    request = Net::HTTP::Delete.new(uri)
  when "POST"
    request = Net::HTTP::Post.new(uri)
    request.body = body if body
  when "PUT"
    request = Net::HTTP::Put.new(uri)
    request.body = body if body
  else
    raise ArgumentError, "Unsupported http method used: #{method}"
  end

  headers.each { |key, value| request[key] = value }
  request
end
