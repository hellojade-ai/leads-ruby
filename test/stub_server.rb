# frozen_string_literal: true

require "json"
require "webrick"

# A scripted stand-in for intake.hellojade.ai. Tests queue responses; every
# request pops the next one and is recorded so headers and bodies can be
# asserted. Nothing here talks to the real API.
class StubServer
  Request = Struct.new(:method, :path, :headers, :body, keyword_init: true) do
    def json
      JSON.parse(body)
    end
  end

  attr_reader :requests, :port

  def initialize
    @responses = Queue.new
    @requests = []
    @mutex = Mutex.new
    @server = WEBrick::HTTPServer.new(
      BindAddress: "127.0.0.1", Port: 0,
      Logger: WEBrick::Log.new(File::NULL), AccessLog: []
    )
    @port = @server.listeners.first.addr[1]
    @server.mount_proc("/") { |req, res| handle(req, res) }
    @thread = Thread.new { @server.start }
  end

  def url
    "http://127.0.0.1:#{@port}"
  end

  # status: Integer; body: Hash (JSON-encoded) or String; headers: Hash;
  # delay: seconds to sleep before answering (to trigger client timeouts).
  def enqueue(status, body = {}, headers: {}, delay: 0)
    @responses << { status: status, body: body, headers: headers, delay: delay }
    self
  end

  def stop
    @server.shutdown
    @thread.join(2)
  end

  private

  def handle(req, res)
    headers = {}
    req.each { |k, v| headers[k.downcase] = v }
    @mutex.synchronize do
      @requests << Request.new(method: req.request_method, path: req.path, headers: headers, body: req.body.to_s)
    end
    scripted = begin
      @responses.pop(true)
    rescue ThreadError
      { status: 500, body: { "error" => "stub_unscripted" }, headers: {}, delay: 0 }
    end
    sleep(scripted[:delay]) if scripted[:delay].positive?
    res.status = scripted[:status]
    res["Content-Type"] = "application/json"
    res["X-Request-Id"] = headers["x-request-id"] || "stub-#{rand(1 << 32).to_s(16)}"
    scripted[:headers].each { |k, v| res[k] = v.to_s }
    body = scripted[:body]
    res.body = body.is_a?(String) ? body : JSON.generate(body)
  end
end
