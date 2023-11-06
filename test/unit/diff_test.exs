defmodule Unit.DiffTest do
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
               changed: [{1, %{left: 2, right: 7}}, {3, %{left: 4, right: 10}}]
             }
    end

    test "shows changes and added_right if both are present" do
      assert Diff.diff([1], [3, 4]) == %{changed: [{0, %{left: 1, right: 3}}], added_right: [4]}
    end

    test "is :unchanged if the lists are equal" do
      assert Diff.diff([1, 2, 3], [1, 2, 3]) == :unchanged
    end

    test "is :unchanged when both lists are empty" do
      assert Diff.diff([], []) == :unchanged
    end

    test "shows the diff for lists in lists" do
      assert Diff.diff([:a, [1, 2], :b], [:a, [1, 4, 3]]) == %{
               added_left: [:b],
               changed: [{1, %{added_right: [3], changed: [{1, %{left: 2, right: 4}}]}}]
             }
    end

    test "shows the diff for maps in lists" do
      assert Diff.diff([:a, %{b: 1, c: 2, d: 5}], [:a, %{b: 1, c: 3}, :e]) == %{
               added_right: [:e],
               changed: [{1, %{added_left: [d: 5], changed: [c: %{left: 2, right: 3}]}}]
             }
    end
  end

  describe "Maps comparison" do
    test "shows :unchanged if they are the same" do
      assert Diff.diff(%{}, %{}) == :unchanged
      assert Diff.diff(%{a: 1, b: 2}, %{a: 1, b: 2}) == :unchanged
      assert Diff.diff(%{a: [1, 2]}, %{a: [1, 2]}) == :unchanged
      assert Diff.diff(%{a: %{a: 1, b: 2}}, %{a: %{a: 1, b: 2}}) == :unchanged
    end

    test "shows added_left if the left map has more keys" do
      assert Diff.diff(%{a: 1, b: 2}, %{a: 1}) == %{added_left: [b: 2]}
    end

    test "shows added_right if the right map has more keys" do
      assert Diff.diff(%{a: 1}, %{a: 1, b: 2}) == %{added_right: [b: 2]}
    end

    test "shows changes" do
      assert Diff.diff(%{a: 1}, %{a: 2}) == %{changed: [a: %{left: 1, right: 2}]}
    end

    test "shows recursive diffs with lists in it" do
      assert Diff.diff(%{a: [1, 2, 3]}, %{a: [1, 2, 4, 5]}) == %{
               changed: [a: %{added_right: [5], changed: [{2, %{left: 3, right: 4}}]}]
             }
    end

    test "shows recursive diffs with maps in it" do
      assert Diff.diff(%{a: %{c: 1, d: 2}}, %{a: %{c: 1, d: 3, e: 4}}) == %{
               changed: [a: %{added_right: [e: 4], changed: [d: %{left: 2, right: 3}]}]
             }
    end
  end

  defmodule MyStruct do
    defstruct [:a, :b]
  end

  describe "Structs comparison" do
    test "shows structs as equal" do
      assert Diff.diff(%MyStruct{a: 1, b: 2}, %MyStruct{a: 1, b: 2}) == :unchanged
    end

    test "shows recursive diffs with maps in it" do
      assert Diff.diff(%MyStruct{a: %{c: 1, d: 2}}, %MyStruct{a: %{c: 1, d: 3, e: 4}}) == %{
               changed: [a: %{added_right: [e: 4], changed: [d: %{left: 2, right: 3}]}]
             }
    end
  end
end
