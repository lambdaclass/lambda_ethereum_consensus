# Fork-choice: LMD GHOST

Let's separate the two parts of the name.

- GHOST: **G**reediest, **H**eaviest-**O**bserved **S**ub-**T**ree. The algorithm provides a strategy to choose between two forks/branches. Each branch points to a block, and each block can be thought of the root of a subtree containing all of its child nodes. The weight of the subtree is the sum of the weights af all blocks in it. The weight in each individual block is obtained from the attestations on them.
- LMD: each validator gives attestations/votes to the block they think is the current head of the chain (Message Driven). "Latest" means that only the last attestation for each validator will be taken into account.

By choosing a fork, each node has a single, linear chain of blocks that it considers canonical. The last child of that chain is called the chain's "head".

## Reacting to an attestation

When an attestation arrives, the `on_attestation` callback must:

1. Perform the [validity checks](https://eth2book.info/capella/part3/forkchoice/phase0/#validate_on_attestation). tl;dr: the slot and epoch need to be right, the vote must be for a block we have, validate the signature and check it doesn't conflict with a different attestation by the same validator.
2. [Save the attestation](https://eth2book.info/capella/part3/forkchoice/phase0/#update_latest_messages) as that validator's latest message. If there's one already, update the value.

## Choosing forks

We now have a store of each validator's latest vote, which allows LMD GHOST to work as a `get_head(store) -> Block` function.

We first need to calculate each block's weight:

- For leaf blocks, we calculate their weight by checking how many votes they have.
- For each branch block we calculate its weight as the sum of the weight of every child, plus its own votes. We repeat this until we reach the root, which will be the last finalized block (there won't be any branches before, so there won't be any more fork-choice to perform).

This way we calculate the weight not only for each block, but for the subtree where that block is the root.

Afterwards, when we want to determine which is the head of the chain, we traverse the tree, starting from the root, and greedily (without looking further ahead) we go block by block chosing the sub-tree with the highest weight.

Let's look at an example:

```mermaid
graph LR

    Genesis --> A[A\nb=10\nw=50]
    Genesis --> B[B\nb=20\nw=20]
    A --> C[C\nb=15\nw=15]
    A --> D[D\nb=25\nw=25]

    classDef chosen fill: #666666
    class Genesis chosen
    class A chosen
    class D chosen
```

Here, individual block weights are represented by "b", while subtree weights are represented by "w". Some observations:

- $W = B$ for all leaf blocks, as leafs are their own whole subtree.
- $W_A=W_C+W_B +B_A= B_B + B_C + B_A$
- While the individual weight of $A$ is smaller than $B$, its children make the $A$ subtree heavier than the $B$ subtree, so its chosen by LMD GHOST over $B$.

In general:

$$W_N = B_N + \sum_i^{i \in \text{children}[N]}W_i$$

## Slashing

In the previous scheme, there are two rewards:

- Proposer rewards, given to a proposer when their block is included in the chain. This also adds an incentive for them to try to predict the most-likely branch to be the canonical one.
- Attester rewards, which are smaller. These are given if the blocks they attest to are included.

These incentives, however, are not enough. To maximize their likelyhood of getting rewards, they may misbehave:

- Proposers may propose a block for every current fork.
- Attesters may attest to every current head in their local chains.

These misbehaviors debilitate the protocol (they give weight to all forks) and no honest node running fork-choice would take part on them. To prevent them, nodes that are detected while doing them are slashed (punished), which means that they are excluded from the validator set and a portion of their stake is burned.

Nodes provide proofs of the offenses, and proposers including them in blocks get whistleblower rewards. Proofs are:

- For proposer slashing: two block headers in the same slot signed by the same signature.
- For attester slashing: two attestations signed in the same slot by the same signature.

## Guarantees

- Majority honest progress: if the network has over 50% nodes running this algorithm honestly, the chain progresses and each older block is exponentially more unlikely to be reverted.
- Stability: fork-choice is self-reinforcing and acts as a good predictor of the next block.
- Manipulation resistence. Not only is it hard to build a secret chain and propose it, but it prevents getting attestations for it, so the current canonical one is always more likely to be heavier. This holds even if the length of the secret chain is higher.
