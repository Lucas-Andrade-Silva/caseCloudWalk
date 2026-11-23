require "rails_helper"

RSpec.describe Experiment::K6Ledger do
  def point(at, ms, status: "201", pmid: "k6-r1-0", redelivery: "false", metric: "http_req_duration")
    { type: "Point", metric: metric,
      data: { time: at, value: ms, tags: { status: status, pmid: pmid, channel: "whatsapp", redelivery: redelivery } } }.to_json
  end

  it "transforma a saída JSON do k6 no ledger dos invariantes, com a fase da rampa de cada envio" do
    lines = [
      { type: "Metric", metric: "http_req_duration", data: {} }.to_json,
      point("2026-11-23T10:00:00.000Z", 12.5),
      point("2026-11-23T10:00:00.000Z", 3.0, metric: "http_req_waiting"),
      point("2026-11-23T10:01:59.000Z", 30.0, pmid: "k6-r1-1"),
      point("2026-11-23T10:02:01.000Z", 99.9, pmid: "k6-r1-0", redelivery: "true", status: "200"),
      point("2026-11-23T10:07:30.000Z", 450.0, pmid: "k6-r1-2", status: "0")
    ]

    ledger = described_class.convert(lines, stages: [ [ "1x", 120 ], [ "10x", 300 ], [ "50x", 180 ] ])

    expect(ledger).to eq([
      { "channel" => "whatsapp", "provider_message_id" => "k6-r1-0", "status" => 201, "ack_ms" => 12.5,
        "redelivery" => false, "stage" => "1x", "offset_s" => 0.0 },
      { "channel" => "whatsapp", "provider_message_id" => "k6-r1-1", "status" => 201, "ack_ms" => 30.0,
        "redelivery" => false, "stage" => "1x", "offset_s" => 119.0 },
      { "channel" => "whatsapp", "provider_message_id" => "k6-r1-0", "status" => 200, "ack_ms" => 99.9,
        "redelivery" => true, "stage" => "10x", "offset_s" => 121.0 },
      { "channel" => "whatsapp", "provider_message_id" => "k6-r1-2", "status" => 0, "ack_ms" => 450.0,
        "redelivery" => false, "stage" => "50x", "offset_s" => 450.0 }
    ])
  end

  it "envio depois da última fase fica na última" do
    ledger = described_class.convert([ point("2026-11-23T10:00:00Z", 1), point("2026-11-23T10:10:00Z", 1, pmid: "b") ],
                                     stages: [ [ "1x", 60 ] ])

    expect(ledger.map { |entry| entry["stage"] }).to eq(%w[1x 1x])
  end
end
