defmodule BeaconApi.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :lambda_ethereum_consensus

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(BeaconApi.Router)
  plug(Sentry.PlugContext)
end
