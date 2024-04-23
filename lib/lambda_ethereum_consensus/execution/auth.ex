defmodule LambdaEthereumConsensus.Execution.Auth do
  @moduledoc """
  JWT generator module for authenticated Engine API communication
  """
  use Joken.Config

  # Set default expiry to 60s
  def token_config(), do: default_claims(default_exp: 60)

  # JWT Authentication is necessary for the EL <> CL communication through Engine API
  # Following the specs here: https://github.com/ethereum/execution-apis/blob/main/src/engine/authentication.md
  # 3 properties are required for the JWT to be valid:
  # 1. The execution layer and consensus layer clients SHOULD accept a configuration parameter: jwt-secret,
  # which designates a file containing the hex-encoded 256 bit secret key to be used for verifying/generating JWT tokens
  # 2. The encoding algorithm used for the JWT generation must be HMAC + SHA256 (HS256)
  # 3. iat (issued-at) claim. The execution layer client SHOULD only accept iat timestamps
  # which are within +-60 seconds from the current time

  @doc """
  Generates a JWT token using HS256 algo and provided secret, additionaly adds an iat claim at current time.
  """
  @spec generate_token(String.t()) :: Joken.bearer_token()
  def generate_token(hex_encoded_secret) do
    jwt_secret =
      hex_encoded_secret
      |> String.trim_leading("0x")
      |> Base.decode16!(case: :mixed)

    signer = Joken.Signer.create("HS256", jwt_secret)
    generate_and_sign!(%{}, signer)
  end
end
