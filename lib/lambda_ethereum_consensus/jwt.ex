defmodule LambdaEthereumConsensus.JWT do
  use Joken.Config

  # JWT Authentication is necessary for the EL <> CL communication through Engine API
  # Following the specs here: https://github.com/ethereum/execution-apis/blob/main/src/engine/authentication.md
  # 3 properties are required for the JWT to be valid:
  # 1. The execution layer and consensus layer clients SHOULD accept a configuration parameter: jwt-secret, which designates a file containing the hex-encoded 256 bit secret key to be used for verifying/generating JWT tokens.
  # 2. The encoding algorithm used for the JWT generation must be HMAC + SHA256 (HS256)
  # 3. iat (issued-at) claim. The execution layer client SHOULD only accept iat timestamps which are within +-60 seconds from the current time.

  @spec generate_token :: {:error, atom | keyword} | {:ok, binary, %{optional(binary) => any}}
  def generate_token() do
    claim = %{"iat" => Joken.current_time()}

    signer =
      Joken.Signer.create(
        "HS256",
        Base.decode16!(
          String.upcase("c4224413b9f85af9a9d1f07962493e646cf7d79f76333bd0a8b901affb558f84")
        )
      )

    generate_and_sign(claim, signer)
  end
end
