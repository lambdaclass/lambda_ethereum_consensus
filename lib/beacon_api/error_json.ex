defmodule BeaconApi.ErrorJSON do
  use BeaconApi, :controller

  @spec render(any, any) :: %{message: String.t()}
  def render(_, _) do
    %{
      message: "There has been an error"
    }
  end
end
