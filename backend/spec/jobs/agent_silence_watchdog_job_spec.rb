require "rails_helper"

RSpec.describe AgentSilenceWatchdogJob do
  it "roda o vigia com o limite de silêncio configurado" do
    watchdog = instance_double(Handoff::AgentSilenceWatchdog, run: 0)
    allow(Handoff::AgentSilenceWatchdog).to receive(:new).and_return(watchdog)

    described_class.new.perform

    expect(Handoff::AgentSilenceWatchdog).to have_received(:new).with(timeout: 30)
    expect(watchdog).to have_received(:run)
  end

  describe "agendamento" do
    let(:schedule) { YAML.load_file(Rails.root.join("config/schedule.yml")) }

    it "está declarado para rodar a cada 5 segundos" do
      entry = schedule.fetch("agent_silence_watchdog")
      cron = Fugit.parse_cron(entry.fetch("cron"))
      first = cron.next_time(Time.utc(2026, 11, 15, 12, 0, 0)).to_t
      second = cron.next_time(first).to_t

      expect(entry.fetch("class")).to eq("AgentSilenceWatchdogJob")
      expect(second - first).to eq(5)
    end

    it "é conferido pelo Sidekiq a cada 5 segundos, não no padrão de 30" do
      expect(Sidekiq::Cron.configuration.cron_poll_interval).to eq(5)
    end
  end
end
