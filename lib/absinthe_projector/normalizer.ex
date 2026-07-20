defmodule AbsintheProjector.Normalizer do
  @moduledoc false

  alias Absinthe.{Resolution, Schema}
  alias Absinthe.Blueprint.Document.Field
  alias Absinthe.Type
  alias AbsintheProjector.{Envelope, Introspection}
  alias AbsintheProjector.Introspection.Association

  @spec normalize(Resolution.t(), module(), [atom()]) :: [Field.t()]
  def normalize(%Resolution{} = resolution, ecto_schema, envelope_path) do
    type = field_type(resolution.definition, resolution.schema)
    path = [field_identifier(resolution.definition)]

    ensure_concrete!(type, path)

    case envelope_path do
      [] -> normalize_entity(resolution, type, ecto_schema, path)
      path_keys -> descend_envelope(resolution, type, ecto_schema, path_keys, path)
    end
  end

  defp descend_envelope(resolution, type, ecto_schema, [key | rest], path) do
    resolution
    |> project_level(type)
    |> Enum.filter(&(field_identifier(&1) == key))
    |> Enum.flat_map(fn field ->
      field_path = path ++ [key]

      case field_type(field, resolution.schema) do
        %Type.Interface{} = abstract ->
          raise_abstract_type!(abstract, field_path)

        %Type.Union{} = abstract ->
          raise_abstract_type!(abstract, field_path)

        %Type.Object{} = object ->
          nested_resolution = nested_resolution(resolution, field)

          case rest do
            [] -> normalize_entity(nested_resolution, object, ecto_schema, field_path)
            keys -> descend_envelope(nested_resolution, object, ecto_schema, keys, field_path)
          end

        nil ->
          # Unit-test and advanced callers may supply already-projected fields
          # without a complete Absinthe schema. Preserve that supported input by
          # falling back to the structural envelope descent in that case.
          Envelope.descend(field.selections, rest)

        _non_object ->
          []
      end
    end)
  end

  defp normalize_entity(resolution, type, ecto_schema, path) do
    associations = Introspection.associations(ecto_schema)

    resolution
    |> project_level(type)
    |> Enum.map(&normalize_association(&1, resolution, associations, path))
  end

  defp normalize_association(%Field{} = field, resolution, associations, path) do
    case associations[field_identifier(field)] do
      %Association{related: related} ->
        normalize_association_children(field, resolution, related, path)

      _not_an_association ->
        field
    end
  end

  defp normalize_association_children(field, resolution, related, path) do
    field_path = path ++ [field_identifier(field)]

    case field_type(field, resolution.schema) do
      %Type.Interface{} = abstract ->
        raise_abstract_type!(abstract, field_path)

      %Type.Union{} = abstract ->
        raise_abstract_type!(abstract, field_path)

      %Type.Object{} = object when field.selections != [] ->
        children =
          resolution
          |> nested_resolution(field)
          |> normalize_entity(object, related, field_path)

        %{field | selections: children}

      _type ->
        field
    end
  end

  defp project_level(resolution, type), do: Resolution.project(resolution, type)

  defp nested_resolution(resolution, field) do
    %{
      resolution
      | definition: field,
        fields_cache: %{},
        path: [field | resolution.path]
    }
  end

  defp field_type(%{schema_node: %{type: type}}, schema) when not is_nil(type) do
    Schema.lookup_type(schema, type)
  end

  defp field_type(_field, _schema), do: nil

  defp ensure_concrete!(%Type.Interface{} = type, path), do: raise_abstract_type!(type, path)
  defp ensure_concrete!(%Type.Union{} = type, path), do: raise_abstract_type!(type, path)
  defp ensure_concrete!(_type, _path), do: :ok

  defp raise_abstract_type!(type, path) do
    location = path |> Enum.reject(&is_nil/1) |> Enum.join(".")

    raise ArgumentError,
          "AbsintheProjector cannot project abstract GraphQL type " <>
            "#{inspect(type.identifier)} at #{location}. The middleware runs before the " <>
            "resolver and cannot know which concrete object type will be returned. " <>
            "Use AbsintheProjector only on fields whose projected path resolves to " <>
            "concrete object types."
  end

  defp field_identifier(%{schema_node: %{identifier: identifier}}), do: identifier
  defp field_identifier(%{name: name}), do: name
  defp field_identifier(_field), do: nil
end
