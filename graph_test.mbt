///|
/// Tests for the dependency graph: neighbourhoods, depth, cycles and execution
/// order.

///|
/// A four step chain: base, then db, then api, then web.
fn chain_plan() -> @moon-change-window-auditor.Plan {
  plan_of(
    "id=base;start=2026-10-01T18:00;end=2026-10-01T19:00\n" +
    "id=db;start=2026-10-01T19:00;end=2026-10-01T20:00;depends=base\n" +
    "id=api;start=2026-10-01T20:00;end=2026-10-01T21:00;depends=db\n" +
    "id=web;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=api\n",
  )
}

///|
test "dependencies_of and dependents_of walk one edge" {
  let plan = chain_plan()
  assert_eq(@moon-change-window-auditor.dependencies_of(plan, "api"), ["db"])
  assert_eq(
    @moon-change-window-auditor.dependencies_of(plan, "base").length(),
    0,
  )
  assert_eq(
    @moon-change-window-auditor.dependencies_of(plan, "missing").length(),
    0,
  )
  assert_eq(@moon-change-window-auditor.dependents_of(plan, "db"), ["api"])
  assert_eq(@moon-change-window-auditor.dependents_of(plan, "base"), ["db"])
  assert_eq(@moon-change-window-auditor.dependents_of(plan, "web").length(), 0)
}

///|
test "transitive_dependencies collects the whole chain once" {
  let plan = chain_plan()
  assert_eq(@moon-change-window-auditor.transitive_dependencies(plan, "web"), [
    "api", "base", "db",
  ])
  assert_eq(
    @moon-change-window-auditor.transitive_dependencies(plan, "base").length(),
    0,
  )
}

///|
test "transitive_dependencies skips ids that are not in the plan" {
  let plan = plan_of(
    "id=a;start=2026-10-01T18:00;end=2026-10-01T19:00;depends=ghost\n",
  )
  assert_eq(@moon-change-window-auditor.dependencies_of(plan, "a"), ["ghost"])
  assert_eq(
    @moon-change-window-auditor.transitive_dependencies(plan, "a").length(),
    0,
  )
  assert_eq(@moon-change-window-auditor.dependency_depth(plan, "a"), 0)
  assert_eq(@moon-change-window-auditor.graph_roots(plan), ["a"])
}

///|
test "dependency_depth is the longest chain below a record" {
  let plan = chain_plan()
  assert_eq(@moon-change-window-auditor.dependency_depth(plan, "base"), 0)
  assert_eq(@moon-change-window-auditor.dependency_depth(plan, "db"), 1)
  assert_eq(@moon-change-window-auditor.dependency_depth(plan, "api"), 2)
  assert_eq(@moon-change-window-auditor.dependency_depth(plan, "web"), 3)
}

///|
test "a diamond collapses to a single depth" {
  let plan = plan_of(
    "id=root;start=2026-10-01T18:00;end=2026-10-01T19:00\n" +
    "id=left;start=2026-10-01T19:00;end=2026-10-01T20:00;depends=root\n" +
    "id=right;start=2026-10-01T19:00;end=2026-10-01T20:00;depends=root\n" +
    "id=join;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=left,right\n",
  )
  assert_eq(@moon-change-window-auditor.transitive_dependencies(plan, "join"), [
    "left", "right", "root",
  ])
  assert_eq(@moon-change-window-auditor.dependency_depth(plan, "join"), 2)
  assert_eq(@moon-change-window-auditor.graph_roots(plan), ["root"])
  assert_eq(@moon-change-window-auditor.graph_leaves(plan), ["join"])
}

///|
test "graph_roots and graph_leaves describe the ends of the chain" {
  let plan = chain_plan()
  assert_eq(@moon-change-window-auditor.graph_roots(plan), ["base"])
  assert_eq(@moon-change-window-auditor.graph_leaves(plan), ["web"])
}

///|
test "an acyclic plan has no cycles" {
  assert_eq(@moon-change-window-auditor.find_cycles(chain_plan()).length(), 0)
}

///|
test "a cycle is reported once, starting at its smallest id" {
  let plan = plan_of(
    "id=b;start=2026-10-01T19:00;end=2026-10-01T20:00;depends=a\n" +
    "id=c;start=2026-10-01T20:00;end=2026-10-01T21:00;depends=b\n" +
    "id=a;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=c\n",
  )
  let cycles = @moon-change-window-auditor.find_cycles(plan)
  assert_eq(cycles.length(), 1)
  // The edges are b -> a -> c -> b, so rotating to the smallest id gives
  // a -> c -> b: a waits for c, c waits for b, b waits for a.
  assert_eq(cycles[0], ["a", "c", "b"])
  assert_eq(
    @moon-change-window-auditor.render_cycle(cycles[0]),
    "a -> c -> b -> a",
  )
}

///|
test "two independent cycles are both reported" {
  let plan = plan_of(
    "id=a;start=2026-10-01T18:00;end=2026-10-01T19:00;depends=b\n" +
    "id=b;start=2026-10-01T19:00;end=2026-10-01T20:00;depends=a\n" +
    "id=x;start=2026-10-01T20:00;end=2026-10-01T21:00;depends=y\n" +
    "id=y;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=x\n",
  )
  let cycles = @moon-change-window-auditor.find_cycles(plan)
  assert_eq(cycles.length(), 2)
  assert_eq(cycles[0], ["a", "b"])
  assert_eq(cycles[1], ["x", "y"])
}

///|
test "a cycle does not make the graph queries loop forever" {
  let plan = plan_of(
    "id=a;start=2026-10-01T18:00;end=2026-10-01T19:00;depends=b\n" +
    "id=b;start=2026-10-01T19:00;end=2026-10-01T20:00;depends=a\n",
  )
  assert_eq(@moon-change-window-auditor.transitive_dependencies(plan, "a"), [
    "b",
  ])
  assert_eq(@moon-change-window-auditor.dependency_depth(plan, "a"), 1)
  assert_eq(@moon-change-window-auditor.execution_order(plan) is None, true)
  assert_eq(
    @moon-change-window-auditor.render_execution_order(
      plan,
      @moon-change-window-auditor.execution_order(plan),
    ),
    "(cyclic)\n",
  )
}

///|
test "execution_order returns a valid order for a chain" {
  let plan = chain_plan()
  match @moon-change-window-auditor.execution_order(plan) {
    Some(order) => assert_eq(order, ["base", "db", "api", "web"])
    None => fail("a chain has an execution order")
  }
  assert_eq(
    @moon-change-window-auditor.render_execution_order(
      plan,
      @moon-change-window-auditor.execution_order(plan),
    ),
    "1. base (2026-10-01T18:00 -> 2026-10-01T19:00)\n" +
    "2. db (2026-10-01T19:00 -> 2026-10-01T20:00)\n" +
    "3. api (2026-10-01T20:00 -> 2026-10-01T21:00)\n" +
    "4. web (2026-10-01T21:00 -> 2026-10-01T22:00)\n",
  )
}

///|
test "execution_order respects dependencies even when times disagree" {
  // The dependent starts before its dependency, so only the graph can order it.
  let plan = plan_of(
    "id=late;start=2026-10-01T20:00;end=2026-10-01T21:00;depends=early\n" +
    "id=early;start=2026-10-01T18:00;end=2026-10-01T19:00\n",
  )
  match @moon-change-window-auditor.execution_order(plan) {
    Some(order) => assert_eq(order, ["early", "late"])
    None => fail("expected an order")
  }
}

///|
test "execution_order ignores a dependency on a missing id" {
  let plan = plan_of(
    "id=a;start=2026-10-01T18:00;end=2026-10-01T19:00;depends=ghost\n" +
    "id=b;start=2026-10-01T19:00;end=2026-10-01T20:00;depends=a\n",
  )
  match @moon-change-window-auditor.execution_order(plan) {
    Some(order) => assert_eq(order, ["a", "b"])
    None => fail("a missing dependency does not block the order")
  }
}

///|
test "execution_order of an empty plan is empty" {
  match @moon-change-window-auditor.execution_order(plan_of("")) {
    Some(order) => assert_eq(order.length(), 0)
    None => fail("an empty plan is ordered")
  }
  assert_eq(
    @moon-change-window-auditor.render_execution_order(plan_of(""), Some([])),
    "(no changes)\n",
  )
}

///|
test "freezes stay outside the dependency graph" {
  let plan = plan_of(
    "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n" +
    "id=a;start=2026-10-01T18:00;end=2026-10-01T19:00\n",
  )
  assert_eq(@moon-change-window-auditor.graph_roots(plan), ["a"])
  assert_eq(@moon-change-window-auditor.graph_leaves(plan), ["a"])
  match @moon-change-window-auditor.execution_order(plan) {
    Some(order) => assert_eq(order, ["a"])
    None => fail("expected an order")
  }
}
