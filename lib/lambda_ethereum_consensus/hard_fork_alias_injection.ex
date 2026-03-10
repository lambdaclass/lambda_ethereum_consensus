defmodule HardForkAliasInjection do
  @moduledoc false
  fork = Application.compile_env!(:lambda_ethereum_consensus, :fork)
  is_deneb = fork == :deneb
  is_fulu = fork == :fulu

  @compile {:inline, deneb?: 0}
  def deneb?(), do: unquote(is_deneb)

  @compile {:inline, fulu?: 0}
  def fulu?(), do: unquote(is_fulu)

  @doc """
  Compiles to the first argument if on deneb, otherwise to the second argument.

  ## Examples

      iex> HardForkAliasInjection.on_deneb(do: true, else: false)
      #{is_deneb}

      iex> HardForkAliasInjection.on_deneb(do: true)
      #{if is_deneb, do: true, else: nil}
  """
  if is_deneb do
    defmacro on_deneb(do: do_clause) do
      do_clause
    end

    defmacro on_deneb(do: do_clause, else: _else_clause) do
      do_clause
    end
  else
    defmacro on_deneb(do: _do_clause) do
      nil
    end

    defmacro on_deneb(do: _do_clause, else: else_clause) do
      else_clause
    end
  end

  @doc """
  Compiles to the first argument if on fulu, otherwise to the second argument.

  ## Examples

      iex> HardForkAliasInjection.on_fulu(do: true, else: false)
      #{is_fulu}

      iex> HardForkAliasInjection.on_fulu(do: true)
      #{if is_fulu, do: true, else: nil}
  """
  if is_fulu do
    defmacro on_fulu(do: do_clause) do
      do_clause
    end

    defmacro on_fulu(do: do_clause, else: _else_clause) do
      do_clause
    end
  else
    defmacro on_fulu(do: _do_clause) do
      nil
    end

    defmacro on_fulu(do: _do_clause, else: else_clause) do
      else_clause
    end
  end
end
