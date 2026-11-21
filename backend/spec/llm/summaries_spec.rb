require "rails_helper"

RSpec.describe Llm::Summaries do
  before { create_brand }

  let(:analyst) { create_analyst("Ana") }

  def capturing_client(summary)
    calls = []
    client = Object.new
    client.define_singleton_method(:calls) { calls }
    client.define_singleton_method(:call) do |task:, input:|
      calls << { task: task, input: input }
      redacted = Llm::Redactor.call(input).text
      calls.last[:redacted] = redacted
      Llm::Client::Result.new(ok: true, data: { "summary" => summary }, source: "replay", error: nil,
                              prompt_version: "#{task}-v1", model: "openai/gpt-oss-120b", key: "k")
    end
    client
  end

  it "melhora o brief do handoff sem apagar o template, que fica de reserva" do
    ticket = escalated_ticket("c-1")
    ticket.append_message!(sender: "customer", body: "meu CPF é 529.982.247-25")
    template = ticket.reload.handoff_brief["summary"]
    client = capturing_client("Cliente quer religar a maquininha; o agente não resolveu.")

    described_class.brief(ticket, client: client)

    brief = ticket.reload.handoff_brief
    expect(brief["summary"]).to eq(template)
    expect(brief).to include("llm_summary" => "Cliente quer religar a maquininha; o agente não resolveu.",
                             "llm_source" => "replay", "llm_prompt_version" => "brief-v1")
    expect(client.calls.sole[:task]).to eq("brief")
    expect(client.calls.sole[:input]).to include("Cliente: meu CPF é")
    expect(client.calls.sole[:redacted]).not_to include("529.982.247-25")
  end

  it "troca o resumo de encerramento pelo do LLM, citando o ticket de origem" do
    ticket = escalated_ticket("c-1")
    ticket.update!(mode: "human", assignee: analyst)
    Tickets::Close.call(ticket: ticket, analyst: analyst, resolution_code: "resolved", resolution_note: "religou")

    described_class.closing(ticket, client: capturing_client("Maquininha não ligava; reinício resolveu."))

    summary = ticket.reload.closing_summary
    expect(summary).to have_attributes(source: "llm", text: "Ticket #{ticket.id}: Maquininha não ligava; reinício resolveu.")
  end

  it "sem LLM, brief e resumo ficam como estão" do
    ticket = escalated_ticket("c-1")
    off = Llm::Client.new(mode: "off")

    described_class.brief(ticket, client: off)

    expect(ticket.reload.handoff_brief).not_to have_key("llm_summary")
  end

  it "a escalação e o fechamento enfileiram os jobs, depois do commit" do
    ticket = escalated_ticket("c-1")
    ticket.update!(mode: "human", assignee: analyst)
    ticket.with_lock { Tickets::Close.call(ticket: ticket, analyst: analyst, resolution_code: "resolved") }

    expect(BriefSummaryJob.jobs.map { |job| job["args"] }).to eq([ [ ticket.id ] ])
    expect(ClosingSummaryJob.jobs.map { |job| job["args"] }).to eq([ [ ticket.id ] ])
  end
end
