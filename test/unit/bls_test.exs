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
end
