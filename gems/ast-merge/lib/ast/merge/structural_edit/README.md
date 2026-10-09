# Ast::Merge::StructuralEdit

`Ast::Merge::StructuralEdit` is the shared home for passive structural edit primitives used by `ast-merge` and the sibling `*-merge` gems.

The namespace is intentionally narrow:

- parser-specific traversal still belongs in the relevant analysis / merger layer
- syntax-aware cleanup still belongs in the relevant family or leaf layer unless it proves cross-format
- structural edit primitives here should preserve untouched source exactly whenever they can

## Core types

### `Boundary`

`Ast::Merge::StructuralEdit::Boundary` captures one surviving edge adjacent to a splice.

A boundary can carry:

- `edge` (`:leading` or `:trailing`)
- `owner`
- `layout_attachment`
- `comment_attachment`
- `metadata`

It is passive metadata for structural edit planning. Replace, remove, and rehome operations can all use the same boundary shape.

### `SplicePlan`

`Ast::Merge::StructuralEdit::SplicePlan` is the first shared primitive.

It models exact contiguous line-range replacement:

- preserve source before the replaced range exactly
- replace only the requested line window
- preserve source after the replaced range exactly

A minimal example:

```ruby
plan = Ast::Merge::StructuralEdit::SplicePlan.new(
  source: source,
  replacement: replacement,
  replace_start_line: 10,
  replace_end_line: 14,
)

plan.before_content
plan.removed_content
plan.after_content
plan.merged_content
plan.apply_to(other_source)
```

### `RemovePlan`

`Ast::Merge::StructuralEdit::RemovePlan` builds on `SplicePlan` for contiguous structural removal.

It keeps the source-preserving removal behavior passive while also recording:

- which owners were removed
- which adjacent owners survived
- which removed comment/layout attachments should be promoted rather than dropped

Blank lines at the junction are capped rather than preserved. Removal's
replacement is always empty, so nothing needs separating from the content that
follows, and the blank run that preceded the removed range already separates the
survivors. Re-emitting the removed owner's trailing separator would either
duplicate it, giving two blank lines at a junction where the source had one, or
invent a leading blank line when the range started the file. `SplicePlan`
therefore ignores `preserve_removed_trailing_blank_lines` for an empty
replacement, and caps any remaining junction run at the longest single
contributing run so a genuine multi-blank separator that lies outside the removed
range survives intact.

Minimal example:

```ruby
plan = Ast::Merge::StructuralEdit::RemovePlan.new(
  source: source,
  remove_start_line: 10,
  remove_end_line: 14,
  leading_boundary: leading_boundary,
  trailing_boundary: trailing_boundary,
  removed_attachments: [removed_attachment],
)

plan.merged_content
plan.apply_to(other_source)
plan.rehome_plans
plan.promoted_comment_regions
plan.promoted_layout_gaps
```

### `PlanSet`

`Ast::Merge::StructuralEdit::PlanSet` batches multiple non-overlapping
splice-compatible edits against one shared original source.

It is the shared general-purpose replacement facade for downstream callers that
need to apply more than one exact structural line-range edit without falling
back to ad hoc line-array surgery.

Minimal example:

```ruby
replace_title = Ast::Merge::StructuralEdit::SplicePlan.new(
  source: source,
  replacement: "# New title\n",
  replace_start_line: 1,
  replace_end_line: 1,
)

remove_old_block = Ast::Merge::StructuralEdit::RemovePlan.new(
  source: source,
  remove_start_line: 10,
  remove_end_line: 14,
)

plan_set = Ast::Merge::StructuralEdit::PlanSet.new(
  source: source,
  plans: [replace_title, remove_old_block],
)

plan_set.merged_content
plan_set.rehome_plans
```

### `RehomePlan`

`Ast::Merge::StructuralEdit::RehomePlan` is the passive transfer record produced by removal planning.

It answers:

- which surviving boundary should receive preserved fragments
- which comment regions survive
- which layout gaps survive
- how those fragments should be exposed as a passive shared attachment for the surviving owner

## Scope

The shared primitives cover:

- contiguous `:replace` by line range (`SplicePlan`)
- contiguous `:remove` plus passive promotion planning (`RemovePlan`)
- passive attachment retargeting to surviving owners (`RehomePlan`)
- batching multiple non-overlapping replace/remove plans against one source (`PlanSet`)

These primitives let callers such as `Ast::Merge::PartialTemplateMergerBase` express source-preserving replacement and removed-section planning without ad hoc separator surgery when the destination analysis exposes real line ranges and attachments.

## Intended next steps

This namespace is the staging ground for richer shared edit operations, including:

- adoption of `RemovePlan` / `RehomePlan` in real removal-mode consumers
- richer edit plans that can distinguish recursive removal, sibling promotion, and explicit ownership-transfer strategies
- edit plans that can reason explicitly about shared `Comment::Region` and `Layout::Gap` ownership in downstream emitters
