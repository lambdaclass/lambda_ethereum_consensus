defmodule BlsTest do
  use ExUnit.Case

  describe "validate_key" do
    test "returns true for valid public key" do
      valid_public_key =
        Base.decode16!(
          "8afc8f134790914b4a15d2fa73b07cafd0d30884fd80ca220c8b9503f5f69c33dd27275b129543d2f7f8f635a81867a0",
          case: :mixed
        )

      assert Bls.key_validate(valid_public_key) == {:ok, true}
    end

    test "returns false for invalid public key" do
      invalid_public_key = <<0::384>>
      assert Bls.key_validate(invalid_public_key) == {:error, "BlstError(BLST_BAD_ENCODING)"}
    end
  end

  describe "Private to public key" do
    test "return the correct public key for a private key" do
      valid_public_key = Base.decode16!("8abb15ca57942b6225af4710bbb74ce8466e99fdc2264d9ffd3b335c7396667e45f537ff1f75ed5afa00585db274f3b6",case: :mixed)
      private_key = Base.decode16!("18363054f52f3f1fdc9ae50d271de853c582c652ebe8dd0f261da3b00cd98984", case: :mixed)
      assert Bls.derive_pubkey(private_key)==valid_public_key
    end
  end

end
