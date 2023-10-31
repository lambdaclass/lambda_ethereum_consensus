defmodule DiffTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Utils.Diff

  describe "Basic comparison" do
    test "shows both sides if different" do
      assert Diff.diff(1, 2) == %{left: 1, right: 2}
    end

    test "shows :unchanged if they are the same" do
      assert Diff.diff(1, 1) == :unchanged
    end
  end

  describe "List comparison" do
    test "shows added_left if the left list has more elements" do
      assert Diff.diff([1, 2, 3, 4], [1, 2]) == %{added_left: [3, 4]}
    end

    test "shows added_right if the right list has more elements" do
      assert Diff.diff([1, 2], [1, 2, 3, 4]) == %{added_right: [3, 4]}
    end

    test "shows changes for equally large lists" do
      assert Diff.diff([1, 2, 3, 4], [1, 7, 3, 10]) == %{
               changed: [%{at: 1, left: 2, right: 7}, %{at: 3, left: 4, right: 10}]
             }
    end

    test "shows changes and added_right if both are present" do
      assert Diff.diff([1], [3, 4]) == %{changed: [%{at: 0, left: 1, right: 3}], added_right: [4]}
    end

    test "is :unchanged if the lists are equal" do
      assert Diff.diff([1, 2, 3], [1, 2, 3]) == :unchanged
    end

    test "is :unchanged when both lists are empty" do
      assert Diff.diff([], []) == :unchanged
    end
  end
end
