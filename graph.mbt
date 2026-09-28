///|
/// Dependency graph queries over a plan.
///
/// Edges point from a change to the windows it depends on. Freezes stay outside
/// the graph: they cannot declare dependencies, and nothing may depend on them.
///
/// A dependency on an id that does not exist is already an audit error; these
/// queries simply ignore such an edge so that a half finished plan can still be
/// inspected.

///|
/// Dependencies declared by one record, or an empty array when the id is not in
/// the plan.
pub fn dependencies_of(plan : Plan, id : String) -> Array[String] {
  match plan.find(id) {
    Some(window) => window.depends
    None => []
  }
}

///|
/// Ids that declare a dependency on the given id, in plan order.
pub fn dependents_of(plan : Plan, id : String) -> Array[String] {
  let dependents : Array[String] = []
  for change in plan.changes() {
    if change.depends.contains(id) {
      dependents.push(change.id)
    }
  }
  dependents
}

///|
/// Depth first walk through the dependencies of `id`, calling `visit` once per
/// id. Ids already on the current path are not visited again, so a cycle cannot
/// make the walk loop.
fn walk_dependencies(
  plan : Plan,
  id : String,
  path : Array[String],
  visit : (String) -> Unit,
) -> Unit {
  for dependency in dependencies_of(plan, id) {
    if path.contains(dependency) {
      continue
    }
    visit(dependency)
    let extended : Array[String] = []
    for step in path {
      extended.push(step)
    }
    extended.push(dependency)
    walk_dependencies(plan, dependency, extended, visit)
  }
}

///|
/// Every id reachable through dependencies, sorted and without duplicates.
///
/// Ids that are not in the plan are reported by the audit as
/// `missing-dependency` and are skipped here.
pub fn transitive_dependencies(plan : Plan, id : String) -> Array[String] {
  let found : Array[String] = []
  let path : Array[String] = [id]
  walk_dependencies(plan, id, path, fn(dependency) {
    if plan.find(dependency) is Some(_) && !found.contains(dependency) {
      found.push(dependency)
    }
  })
  distinct_strings(found)
}

///|
/// Length of the longest dependency chain below an id, `0` when it has none.
///
/// A cycle cannot extend a chain: the walk stops when it meets an id that is
/// already on the path, and `find_cycles` reports the cycle itself.
pub fn dependency_depth(plan : Plan, id : String) -> Int {
  deepest_dependency_depth(plan, id, [id])
}

///|
/// Recursive helper of `dependency_depth`.
fn deepest_dependency_depth(
  plan : Plan,
  id : String,
  path : Array[String],
) -> Int {
  let mut deepest = 0
  for dependency in dependencies_of(plan, id) {
    if path.contains(dependency) || plan.find(dependency) is None {
      continue
    }
    let extended : Array[String] = []
    for step in path {
      extended.push(step)
    }
    extended.push(dependency)
    let depth = 1 + deepest_dependency_depth(plan, dependency, extended)
    if depth > deepest {
      deepest = depth
    }
  }
  deepest
}

///|
/// Rotate a cycle so that it starts at its smallest id, which makes the same
/// cycle comparable no matter where the walk entered it.
fn canonical_cycle(ids : Array[String]) -> Array[String] {
  if ids.length() == 0 {
    return ids
  }
  let mut smallest = 0
  let mut index = 1
  while index < ids.length() {
    if compare_strings(ids[index], ids[smallest]) < 0 {
      smallest = index
    }
    index = index + 1
  }
  let rotated : Array[String] = []
  let mut offset = 0
  while offset < ids.length() {
    rotated.push(ids[(smallest + offset) % ids.length()])
    offset = offset + 1
  }
  rotated
}

///|
/// True when both arrays hold the same ids in the same order.
fn same_cycle(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut index = 0
  while index < left.length() {
    if left[index] != right[index] {
      return false
    }
    index = index + 1
  }
  true
}

///|
/// Search for cycles reachable from one id.
fn collect_cycles(
  plan : Plan,
  id : String,
  path : Array[String],
  cycles : Array[Array[String]],
) -> Unit {
  for dependency in dependencies_of(plan, id) {
    if plan.find(dependency) is None {
      continue
    }
    let position = index_of_string(path, dependency)
    if position >= 0 {
      let cycle : Array[String] = []
      let mut index = position
      while index < path.length() {
        cycle.push(path[index])
        index = index + 1
      }
      let canonical = canonical_cycle(cycle)
      let mut known = false
      for existing in cycles {
        if same_cycle(existing, canonical) {
          known = true
        }
      }
      if !known {
        cycles.push(canonical)
      }
      continue
    }
    let extended : Array[String] = []
    for step in path {
      extended.push(step)
    }
    extended.push(dependency)
    collect_cycles(plan, dependency, extended, cycles)
  }
}

///|
/// Position of a value in an array, or `-1`.
fn index_of_string(values : Array[String], value : String) -> Int {
  let mut index = 0
  while index < values.length() {
    if values[index] == value {
      return index
    }
    index = index + 1
  }
  -1
}

///|
/// Every dependency cycle in the plan, each one once.
///
/// A cycle is rendered as the ids in walk order starting from its smallest id,
/// and the list is ordered by that first id. Cyclic plans cannot be ordered, so
/// `execution_order` returns `None` for them.
pub fn find_cycles(plan : Plan) -> Array[Array[String]] {
  let cycles : Array[Array[String]] = []
  let visited : Array[String] = []
  for change in plan.changes() {
    if visited.contains(change.id) {
      continue
    }
    collect_cycles(plan, change.id, [change.id], cycles)
    visited.push(change.id)
  }
  sort_cycles(cycles)
}

///|
/// Order cycles by their first id, then by length.
fn sort_cycles(cycles : Array[Array[String]]) -> Array[Array[String]] {
  let ordered : Array[Array[String]] = []
  for cycle in cycles {
    ordered.push(cycle)
  }
  let mut index = 1
  while index < ordered.length() {
    let current = ordered[index]
    let mut position = index
    while position > 0 && cycle_before(current, ordered[position - 1]) {
      ordered[position] = ordered[position - 1]
      position = position - 1
    }
    ordered[position] = current
    index = index + 1
  }
  ordered
}

///|
/// True when the first cycle should be reported before the second one.
fn cycle_before(left : Array[String], right : Array[String]) -> Bool {
  if left.length() == 0 || right.length() == 0 {
    return left.length() < right.length()
  }
  let order = compare_strings(left[0], right[0])
  if order != 0 {
    return order < 0
  }
  left.length() < right.length()
}

///|
/// Render one cycle as `a -> b -> a`.
pub fn render_cycle(cycle : Array[String]) -> String {
  if cycle.length() == 0 {
    return ""
  }
  let builder = StringBuilder()
  for id in cycle {
    builder.write_string(id)
    builder.write_string(" -> ")
  }
  builder.write_string(cycle[0])
  builder.to_string()
}

///|
/// Changes that declare no dependency on a record that exists, in plan order.
///
/// A dependency on a missing id is ignored here: the audit reports it, and the
/// change still has nothing to wait for.
pub fn graph_roots(plan : Plan) -> Array[String] {
  let roots : Array[String] = []
  for change in plan.changes() {
    let mut waits = false
    for dependency in change.depends {
      if plan.find(dependency) is Some(_) {
        waits = true
      }
    }
    if !waits {
      roots.push(change.id)
    }
  }
  roots
}

///|
/// Changes that no other change waits for, in plan order.
pub fn graph_leaves(plan : Plan) -> Array[String] {
  let leaves : Array[String] = []
  for change in plan.changes() {
    if dependents_of(plan, change.id).length() == 0 {
      leaves.push(change.id)
    }
  }
  leaves
}

///|
/// An order in which the changes can run so that every dependency comes first.
///
/// Ties are broken by start minute and then by id, so the order is a pure
/// function of the plan. Dependencies on missing ids are ignored, and `None`
/// means the plan contains a cycle.
pub fn execution_order(plan : Plan) -> Array[String]? {
  let remaining = sort_windows_by_start(plan.changes())
  let done : Array[String] = []
  let order : Array[String] = []
  while order.length() < plan.changes().length() {
    let mut chosen : Window? = None
    for candidate in remaining {
      if done.contains(candidate.id) {
        continue
      }
      let mut ready = true
      for dependency in candidate.depends {
        if plan.find(dependency) is Some(_) && !done.contains(dependency) {
          ready = false
        }
      }
      if ready {
        chosen = Some(candidate)
        break
      }
    }
    match chosen {
      None => return None
      Some(window) => {
        order.push(window.id)
        done.push(window.id)
      }
    }
  }
  Some(order)
}

///|
/// Render an execution order as `1. database` lines, or `(cyclic)` when the
/// plan cannot be ordered.
pub fn render_execution_order(plan : Plan, order : Array[String]?) -> String {
  let builder = StringBuilder()
  match order {
    None => builder.write_string("(cyclic)\n")
    Some(ids) =>
      if ids.length() == 0 {
        builder.write_string("(no changes)\n")
      } else {
        for index = 0; index < ids.length(); index = index + 1 {
          builder.write_string((index + 1).to_string())
          builder.write_string(". ")
          builder.write_string(ids[index])
          match plan.find(ids[index]) {
            Some(window) =>
              builder.write_string(
                " (" +
                format_instant(window.start) +
                " -> " +
                format_instant(window.end) +
                ")",
              )
            None => ()
          }
          builder.write_char('\n')
        }
      }
  }
  builder.to_string()
}
