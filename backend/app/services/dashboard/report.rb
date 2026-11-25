module Dashboard
  # Base dos relatórios do Painel: a janela de 7 dias (contando hoje, no fuso da operação), o escopo de marcas e
  # as contas de média e mediana. brand_ids nil quer dizer todas as marcas (operação).
  class Report
    DAYS = 7

    def self.call(...) = new(...).call

    def initialize(brand_ids:, now: Time.current, zone: ENV.fetch("DASHBOARD_TIME_ZONE", "America/Sao_Paulo"))
      @brand_ids = brand_ids
      @now = now
      @zone = ActiveSupport::TimeZone[zone] || ActiveSupport::TimeZone["UTC"]
      @today = @now.in_time_zone(@zone).beginning_of_day
      @window_start = @today - (DAYS - 1).days
    end

    private

    def tickets = @brand_ids ? Ticket.where(brand_id: @brand_ids) : Ticket.all

    def window = @window_start..@now

    def window_dates = (0...DAYS).map { |offset| (@window_start + offset.days).to_date }

    def local_date(time) = time.in_time_zone(@zone).to_date

    def header = { generated_at: @now.iso8601(3), time_zone: @zone.tzinfo.name }

    def mean(values)
      values.empty? ? nil : (values.sum / values.size.to_f).round
    end

    def median(values)
      return nil if values.empty?

      sorted = values.sort
      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2.0).round
    end

    def percent(part, total) = total.zero? ? nil : (part * 100.0 / total).round
  end
end
