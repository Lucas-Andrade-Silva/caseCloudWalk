require "rails_helper"

# Corpo JSON tolerante das rotas de interface: só objetos valem; o resto vira {}.
RSpec.describe JsonBody, type: :controller do
  controller(ApplicationController) do
    include JsonBody

    def index
      render json: { body: json_body }
    end
  end

  it "lê um objeto JSON e trata corpo vazio, inválido ou não-objeto como {}" do
    { '{"a":1}' => { "a" => 1 }, "" => {}, "{x" => {}, "[1,2]" => {} }.each do |raw, expected|
      get :index, body: raw
      expect(response.parsed_body["body"]).to eq(expected), "corpo #{raw.inspect}"
    end
  end
end
