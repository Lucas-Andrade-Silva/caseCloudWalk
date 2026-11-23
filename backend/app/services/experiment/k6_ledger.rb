module Experiment
  # Converte a saída JSON do k6 (`--out json=...`) no ledger que o verificador de invariantes usa (playbook §9).
  # Cada requisição do webhook vira uma entrada com status, ACK em ms, se era reentrega e a fase da rampa em que
  # saiu (pelo tempo desde o primeiro envio e a duração de cada fase).
  module K6Ledger
    METRIC = "http_req_duration".freeze

    module_function

    # `stages`: [[nome, duração em segundos], ...] na ordem da rampa.
    def convert(lines, stages:)
      points = lines.filter_map { |line| parse(line) }.sort_by { |point| point[:time] }
      return [] if points.empty?

      start = points.first[:time]
      points.map do |point|
        offset = (point[:time] - start).round(3)
        tags = point[:tags]
        { "channel" => tags["channel"], "provider_message_id" => tags["pmid"], "status" => tags["status"].to_i,
          "ack_ms" => point[:value], "redelivery" => tags["redelivery"] == "true",
          "stage" => stage_at(offset, stages), "offset_s" => offset }
      end
    end

    def parse(line)
      data = JSON.parse(line)
      return unless data["type"] == "Point" && data["metric"] == METRIC

      tags = data.dig("data", "tags") || {}
      return unless tags["pmid"]

      { time: Time.iso8601(data.dig("data", "time")).to_f, value: data.dig("data", "value").to_f, tags: tags }
    rescue JSON::ParserError, ArgumentError
      nil
    end

    def stage_at(offset, stages)
      elapsed = 0
      stages.each do |name, seconds|
        elapsed += seconds
        return name if offset < elapsed
      end
      stages.last&.first
    end
  end
end
