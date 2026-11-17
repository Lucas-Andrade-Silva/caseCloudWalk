# Eventos do mapa vivo de uma marca (ADR 0007, I13). O analista só assina as marcas que atende; a operação,
# qualquer uma.
class MapChannel < ApplicationCable::Channel
  def subscribed
    brand = Brand.find_by(slug: params[:brand])
    return reject unless brand && allowed?(brand)

    stream_from Live::MapBroadcast.stream(brand.slug)
  end

  private

  def allowed?(brand)
    current_user.role == "ops" || current_user.brand_ids.include?(brand.id)
  end
end
