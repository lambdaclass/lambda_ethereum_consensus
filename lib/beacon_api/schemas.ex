defmodule BeaconApi.Schemas do
  @moduledoc false
  alias OpenApiSpex.Schema

  defmodule SuccessStateRootResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        execution_optimistic: %Schema{type: :boolean},
        finalized: %Schema{type: :boolean},
        data: %Schema{
          type: :object,
          properties: %{
            root: %Schema{type: :string}
          }
        }
      },
      example: %{
        "execution_optimistic" => false,
        "finalized" => false,
        "data" => %{
          "root" => "0xcf8e0d4e9587369b2301d0790347320302cc0943d5a1884560367e8208d920f2"
        }
      }
    })
  end

  defmodule InvalidStateRootResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        code: %Schema{type: :integer},
        message: %Schema{type: :string}
      },
      example: %{
        "code" => 400,
        "message" => "Invalid state ID: current"
      }
    })
  end

  defmodule StateNotFoundStateRootResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        code: %Schema{type: :integer},
        message: %Schema{type: :string}
      },
      example: %{
        "code" => 400,
        "message" => "State not found"
      }
    })
  end

  defmodule InternalErrorStateRootResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        code: %Schema{type: :integer},
        message: %Schema{type: :string}
      },
      example: %{
        "code" => 400,
        "message" => "Internal server error"
      }
    })
  end
end
