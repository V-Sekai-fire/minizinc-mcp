# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Converter do
  @moduledoc """
  Converts planner elements (actions, tasks, commands, multigoals) to MiniZinc format
  using Elixir's Code module to parse and transform Elixir AST.

  ## Overview

  This module uses Elixir's built-in Code module to parse Elixir code from planner elements and convert
  them into MiniZinc constraint programming models. It extracts:

  - **Preconditions**: Converted to MiniZinc constraints
  - **Effects**: Converted to MiniZinc variable assignments
  - **Predicates**: Converted to MiniZinc decision variables
  - **Logic**: Converted to MiniZinc constraint expressions

  ## Usage

      # Convert a command module to MiniZinc
      {:ok, minizinc_code} = MiniZincConverter.convert_command(
        AriaPlanner.Domains.TinyCvrp.Commands.VisitCustomer
      )

      # Convert a task module to MiniZinc
      {:ok, minizinc_code} = MiniZincConverter.convert_task(
        AriaPlanner.Domains.TinyCvrp.Tasks.RouteVehicles
      )

      # Convert a multigoal module to MiniZinc
      {:ok, minizinc_code} = MiniZincConverter.convert_multigoal(
        AriaPlanner.Domains.TinyCvrp.Multigoals.RouteVehicles
      )

      # Convert a planning domain to MiniZinc
      {:ok, minizinc_code} = MiniZincConverter.convert_domain(domain)
  """

  # Note: AriaCore.PlanningDomain is optional - if not available, use map() instead
  # alias AriaCore.PlanningDomain

  @doc """
  Converts a command module to MiniZinc format.

  Extracts preconditions, effects, and logic from the command's Elixir code
  and converts them to MiniZinc constraints and variable declarations.
  """
  @spec convert_command(module() | String.t() | map()) :: {:ok, String.t()} | {:error, String.t()}
  def convert_command(module) when is_atom(module) do
    case get_module_source(module) do
      {:ok, source} ->
        convert_command_source(source, module)

      error ->
        error
    end
  end

  def convert_command(module_string) when is_binary(module_string) do
    case Code.string_to_quoted(module_string) do
      {:ok, ast} ->
        convert_command_ast(ast)

      error ->
        {:error, "Failed to parse module: #{inspect(error)}"}
    end
  end

  def convert_command(cmd) when is_map(cmd) do
    convert_command_element(cmd)
  end

  @doc """
  Converts a task module to MiniZinc format.

  Extracts task decomposition logic and converts it to MiniZinc constraints.
  """
  @spec convert_task(module() | String.t() | map()) :: {:ok, String.t()} | {:error, String.t()}
  def convert_task(module) when is_atom(module) do
    case get_module_source(module) do
      {:ok, source} ->
        convert_task_source(source, module)

      error ->
        error
    end
  end

  def convert_task(module_string) when is_binary(module_string) do
    case Code.string_to_quoted(module_string) do
      {:ok, ast} ->
        convert_task_ast(ast)

      error ->
        {:error, "Failed to parse module: #{inspect(error)}"}
    end
  end

  def convert_task(task) when is_map(task) do
    convert_task_element(task)
  end

  @doc """
  Converts a multigoal module to MiniZinc format.

  Extracts goal generation logic and converts it to MiniZinc constraints.
  """
  @spec convert_multigoal(module() | String.t() | map()) ::
          {:ok, String.t()} | {:error, String.t()}
  def convert_multigoal(module) when is_atom(module) do
    case get_module_source(module) do
      {:ok, source} ->
        convert_multigoal_source(source, module)

      error ->
        error
    end
  end

  def convert_multigoal(module_string) when is_binary(module_string) do
    case Code.string_to_quoted(module_string) do
      {:ok, ast} ->
        convert_multigoal_ast(ast)

      error ->
        {:error, "Failed to parse module: #{inspect(error)}"}
    end
  end

  def convert_multigoal(mg) when is_map(mg) do
    convert_multigoal_element(mg)
  end

  @doc """
  Converts an entire planning domain to MiniZinc format.

  Combines all domain elements (commands, tasks, multigoals) into a single
  MiniZinc model.
  """
  @spec convert_domain(map()) :: {:ok, String.t()} | {:error, String.t()}
  def convert_domain(domain_map) when is_map(domain_map) do
    convert_domain_from_maps(domain_map)
  end

  @doc """
  Converts a domain to MiniZinc and saves it to a file.

  ## Parameters

  - `domain`: Planning domain to convert
  - `output_path`: Path to save the .mzn file

  ## Returns

  - `{:ok, path}` - Path to saved file
  - `{:error, reason}` - Error reason
  """
  @spec convert_domain_to_file(map(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def convert_domain_to_file(domain, output_path) do
    case convert_domain(domain) do
      {:ok, minizinc_code} ->
        case File.write(output_path, minizinc_code) do
          :ok -> {:ok, output_path}
          {:error, reason} -> {:error, "Failed to write file: #{inspect(reason)}"}
        end

      error ->
        error
    end
  end

  @doc """
  Converts a domain to MiniZinc and solves it using MiniZincSolver.

  ## Parameters

  - `domain`: Planning domain to convert and solve
  - `data_path`: Optional path to .dzn data file
  - `opts`: Options keyword list (passed to MiniZincSolver.solve)

  ## Returns

  - `{:ok, solution}` - Parsed solution
  - `{:error, reason}` - Error reason
  """
  @spec convert_and_solve(map(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def convert_and_solve(domain, data_path \\ nil, opts \\ []) do
    case convert_domain(domain) do
      {:ok, minizinc_code} ->
        MiniZincMcp.Solver.solve_string(minizinc_code, data_path, opts)

      error ->
        error
    end
  end

  # Private helper functions

  defp get_module_source(module) do
    # Try to get the source file path
    source_file = module.__info__(:compile)[:source]

    if source_file do
      case File.read(source_file) do
        {:ok, source} -> {:ok, source}
        error -> {:error, "Failed to read source file: #{inspect(error)}"}
      end
    else
      {:error, "Could not find source file for module #{inspect(module)}"}
    end
  rescue
    _ -> {:error, "Module #{inspect(module)} does not exist or is not compiled"}
  end

  defp convert_command_source(source, module) do
    {:ok, ast} = Code.string_to_quoted(source)
    convert_command_ast(ast)
  rescue
    error ->
      {:error, "Failed to parse source for #{inspect(module)}: #{inspect(error)}"}
  end

  defp convert_command_ast(ast) do
    # Extract command function (c_*)
    command_func = find_command_function(ast)
    preconditions = extract_preconditions(ast)
    effects = extract_effects(ast)
    predicates = extract_predicates(ast)

    minizinc =
      generate_minizinc_model(
        command_func,
        preconditions,
        effects,
        predicates
      )

    {:ok, minizinc}
  end

  defp convert_task_source(source, module) do
    {:ok, ast} = Code.string_to_quoted(source)
    convert_task_ast(ast)
  rescue
    error ->
      {:error, "Failed to parse source for #{inspect(module)}: #{inspect(error)}"}
  end

  defp convert_task_ast(ast) do
    # Extract task function (t_*)
    task_func = find_task_function(ast)
    decomposition = extract_decomposition(ast)
    predicates = extract_predicates(ast)

    minizinc =
      generate_task_minizinc(
        task_func,
        decomposition,
        predicates
      )

    {:ok, minizinc}
  end

  defp convert_multigoal_source(source, module) do
    {:ok, ast} = Code.string_to_quoted(source)
    convert_multigoal_ast(ast)
  rescue
    error ->
      {:error, "Failed to parse source for #{inspect(module)}: #{inspect(error)}"}
  end

  defp convert_multigoal_ast(ast) do
    # Extract multigoal function (m_*)
    multigoal_func = find_multigoal_function(ast)
    goals = extract_goals(ast)
    predicates = extract_predicates(ast)

    minizinc =
      generate_multigoal_minizinc(
        multigoal_func,
        goals,
        predicates
      )

    {:ok, minizinc}
  end

  defp convert_domain_from_maps(domain) do
    commands = Map.get(domain, :commands, []) || []
    actions = Map.get(domain, :actions, []) || []
    tasks = Map.get(domain, :tasks, []) || []
    multigoals = Map.get(domain, :multigoals, []) || []
    predicates = Map.get(domain, :predicates, []) || []
    entities = Map.get(domain, :entities, []) || []

    domain_name = Map.get(domain, :name, "domain") || Map.get(domain, :domain_type, "domain")

    # Convert actions to commands format for processing
    all_commands =
      commands ++
        Enum.map(actions, fn action ->
          %{
            "name" => Map.get(action, "name") || Map.get(action, :name),
            "preconditions" =>
              Map.get(action, "preconditions", []) || Map.get(action, :preconditions, []),
            "effects" => Map.get(action, "effects", []) || Map.get(action, :effects, [])
          }
        end)

    # Generate variable declarations from predicates
    variable_declarations = generate_variable_declarations(predicates, entities)

    # Convert each element (commands and actions)
    command_constraints =
      Enum.map(all_commands, fn cmd ->
        case convert_command_element(cmd) do
          {:ok, model} -> extract_constraints_from_model(model)
          _ -> []
        end
      end)
      |> List.flatten()

    task_constraints =
      Enum.map(tasks, fn task ->
        case convert_task_element(task) do
          {:ok, model} -> extract_constraints_from_model(model)
          _ -> []
        end
      end)
      |> List.flatten()

    multigoal_constraints =
      Enum.map(multigoals, fn mg ->
        case convert_multigoal_element(mg) do
          {:ok, model} -> extract_constraints_from_model(model)
          _ -> []
        end
      end)
      |> List.flatten()

    # Combine into single MiniZinc model
    minizinc = """
    % MiniZinc model for domain: #{domain_name}
    % Generated from planner elements

    % Variable declarations
    #{if variable_declarations != "", do: variable_declarations, else: "% No variables declared"}

    % Constraints from commands
    #{if command_constraints != [], do: "% Commands\n" <> Enum.join(command_constraints, "\n"), else: "% No command constraints"}

    % Constraints from tasks
    #{if task_constraints != [], do: "% Tasks\n" <> Enum.join(task_constraints, "\n"), else: "% No task constraints"}

    % Constraints from multigoals
    #{if multigoal_constraints != [], do: "% Multigoals\n" <> Enum.join(multigoal_constraints, "\n"), else: "% No multigoal constraints"}

    solve satisfy;
    """

    {:ok, minizinc}
  end

  defp generate_variable_declarations(predicates, entities) do
    # Generate variable declarations for predicates
    predicate_vars =
      Enum.map_join(predicates, "\n", fn pred ->
        pred_name =
          if is_binary(pred),
            do: pred,
            else: Map.get(pred, "name") || Map.get(pred, :name) || "unknown"

        "var bool: #{pred_name};"
      end)

    # Generate variable declarations for entities if needed
    entity_vars =
      Enum.map_join(entities, "\n", fn entity ->
        entity_name =
          if is_binary(entity),
            do: entity,
            else: Map.get(entity, "name") || Map.get(entity, :name) || "unknown"

        "var int: #{entity_name};"
      end)

    [predicate_vars, entity_vars]
    |> Enum.filter(&(&1 != ""))
    |> Enum.join("\n")
  end

  defp extract_constraints_from_model(model) when is_binary(model) do
    # Extract constraint lines from model string
    model
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.trim(line) |> String.starts_with?("constraint")
    end)
  end

  defp extract_constraints_from_model(_), do: []

  defp convert_command_element(cmd) when is_map(cmd) do
    name = Map.get(cmd, "name") || Map.get(cmd, :name)
    preconditions = Map.get(cmd, "preconditions", []) || Map.get(cmd, :preconditions, [])
    effects = Map.get(cmd, "effects", []) || Map.get(cmd, :effects, [])

    if name do
      minizinc = generate_command_minizinc_from_map(name, preconditions, effects)
      {:ok, minizinc}
    else
      {:error, "Command missing name"}
    end
  end

  defp convert_task_element(task) when is_map(task) do
    name = Map.get(task, "name") || Map.get(task, :name)
    decomposition = Map.get(task, "decomposition") || Map.get(task, :decomposition)

    if name do
      minizinc = generate_task_minizinc_from_map(name, decomposition)
      {:ok, minizinc}
    else
      {:error, "Task missing name"}
    end
  end

  defp convert_multigoal_element(mg) when is_map(mg) do
    name = Map.get(mg, "name") || Map.get(mg, :name)
    predicate = Map.get(mg, "predicate") || Map.get(mg, :predicate)

    if name do
      minizinc = generate_multigoal_minizinc_from_map(name, predicate)
      {:ok, minizinc}
    else
      {:error, "Multigoal missing name"}
    end
  end

  # AST traversal functions using Macro.postwalk

  defp find_command_function(ast) do
    # Find function definition starting with c_
    {_, result} =
      Macro.postwalk(ast, nil, fn
        {:def, _, [{name, _, _}, _, _], _} = node, acc ->
          func_name_str = if is_atom(name), do: Atom.to_string(name), else: to_string(name)

          if String.starts_with?(func_name_str, "c_") do
            {node, name}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp find_task_function(ast) do
    # Find function definition starting with t_
    {_, result} =
      Macro.postwalk(ast, nil, fn
        {:def, _, [{name, _, _}, _, _], _} = node, acc ->
          func_name_str = if is_atom(name), do: Atom.to_string(name), else: to_string(name)

          if String.starts_with?(func_name_str, "t_") do
            {node, name}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp find_multigoal_function(ast) do
    # Find function definition starting with m_
    {_, result} =
      Macro.postwalk(ast, nil, fn
        {:def, _, [{name, _, _}, _, _], _} = node, acc ->
          func_name_str = if is_atom(name), do: Atom.to_string(name), else: to_string(name)

          if String.starts_with?(func_name_str, "m_") do
            {node, name}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp extract_preconditions(ast) do
    # Extract preconditions from with/2 clauses or guard patterns
    preconditions = []

    {_, preconditions} =
      Macro.postwalk(ast, preconditions, fn
        {:with, _, [clauses, _]} = node, acc ->
          # Extract conditions from with clauses
          conditions = extract_with_conditions(clauses)
          {node, acc ++ conditions}

        {:if, _, [condition, _]} = node, acc ->
          # Extract if conditions
          {node, acc ++ [condition]}

        node, acc ->
          {node, acc}
      end)

    preconditions
  end

  defp extract_effects(ast) do
    # Extract effects from assignments and predicate updates
    effects = []

    {_, effects} =
      Macro.postwalk(ast, effects, fn
        {:=, _, [left, right]} = node, acc ->
          # Assignment
          {node, acc ++ [{left, right}]}

        {:|>, _, [arg, {:., _, [{:__aliases__, _, path}, :set]}]} = node, acc ->
          # Predicate set operation
          predicate_name = Enum.map_join(path, ".", &to_string/1)
          {node, acc ++ [{:predicate_set, predicate_name, arg}]}

        node, acc ->
          {node, acc}
      end)

    effects
  end

  defp extract_predicates(ast) do
    # Extract predicate references from module aliases
    predicates = []

    {_, predicates} =
      Macro.postwalk(ast, predicates, fn
        {:alias, _, [{:__aliases__, _, path}]} = node, acc ->
          # Check if it's a Predicate module
          path_str = Enum.map_join(path, ".", &to_string/1)

          if String.contains?(path_str, "Predicate") do
            {node, acc ++ [path_str]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    predicates
  end

  defp extract_decomposition(ast) do
    # Extract task decomposition (list of subtasks)
    decomposition = []

    {_, decomposition} =
      Macro.postwalk(ast, decomposition, fn
        {:list, _, elements} = node, acc ->
          # List of subtasks
          {node, acc ++ elements}

        node, acc ->
          {node, acc}
      end)

    decomposition
  end

  defp extract_goals(ast) do
    # Extract goals from comprehension or list
    goals = []

    {_, goals} =
      Macro.postwalk(ast, goals, fn
        {:for, _, generators} = node, acc ->
          # List comprehension generating goals
          {node, acc ++ generators}

        {:list, _, elements} = node, acc ->
          # List of goals
          {node, acc ++ elements}

        node, acc ->
          {node, acc}
      end)

    goals
  end

  defp extract_with_conditions(clauses) do
    # Extract conditions from with clauses
    case clauses do
      [{:<-, _, [_, condition]}] -> [condition]
      [{:<-, _, [_, condition]} | rest] -> [condition | extract_with_conditions(rest)]
      _ -> []
    end
  end

  # MiniZinc generation functions

  defp generate_minizinc_model(command_func, preconditions, effects, predicates) do
    func_name = format_function_name(command_func)

    """
    % Command: #{func_name}
    % Preconditions:
    #{format_preconditions(preconditions)}
    % Effects:
    #{format_effects(effects)}
    % Predicates:
    #{format_predicates(predicates)}
    """
  end

  defp generate_task_minizinc(task_func, decomposition, predicates) do
    func_name = format_function_name(task_func)

    """
    % Task: #{func_name}
    % Decomposition:
    #{format_decomposition(decomposition)}
    % Predicates:
    #{format_predicates(predicates)}
    """
  end

  defp generate_multigoal_minizinc(multigoal_func, goals, predicates) do
    func_name = format_function_name(multigoal_func)

    """
    % Multigoal: #{func_name}
    % Goals:
    #{format_goals(goals)}
    % Predicates:
    #{format_predicates(predicates)}
    """
  end

  defp generate_command_minizinc_from_map(name, preconditions, effects) do
    # Convert preconditions to MiniZinc constraints
    constraint_lines =
      preconditions
      |> Enum.map(&convert_precondition_to_constraint/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.join("\n")

    # Convert effects to variable assignments or constraints
    effect_lines =
      effects
      |> Enum.map(&convert_effect_to_minizinc/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.join("\n")

    """
    % Command: #{name}
    #{if constraint_lines != "", do: constraint_lines, else: "% No preconditions"}
    #{if effect_lines != "", do: effect_lines, else: "% No effects"}
    % End Command: #{name}
    """
  end

  defp generate_task_minizinc_from_map(name, decomposition) do
    """
    % Task: #{name}
    % Decomposition: #{decomposition || "N/A"}
    % Tasks are decomposed into subtasks during planning
    """
  end

  defp generate_multigoal_minizinc_from_map(name, predicate) do
    goal_constraint =
      if predicate do
        "constraint #{predicate} = true;"
      else
        "% Goal: #{name}"
      end

    """
    % Multigoal: #{name}
    #{goal_constraint}
    """
  end

  defp convert_precondition_to_constraint(prec) when is_binary(prec) do
    # Try to parse as an expression first
    normalized = normalize_expression_string(prec)

    case Code.string_to_quoted(normalized) do
      {:ok, ast} ->
        convert_ast_to_minizinc_constraint(ast)

      {:error, _} ->
        # If parsing fails, return error message
        "% Precondition (could not parse): #{prec}"
    end
  end

  defp convert_precondition_to_constraint(ast) when is_tuple(ast) do
    convert_ast_to_minizinc_constraint(ast)
  end

  defp convert_precondition_to_constraint(_), do: ""

  defp convert_effect_to_minizinc(effect) when is_binary(effect) do
    # Try to parse as an expression first
    normalized = normalize_expression_string(effect)

    case Code.string_to_quoted(normalized) do
      {:ok, ast} ->
        convert_ast_to_minizinc_effect(ast)

      {:error, _} ->
        # If parsing fails, return error message
        "% Effect (could not parse): #{effect}"
    end
  end

  defp convert_effect_to_minizinc(ast) when is_tuple(ast) do
    convert_ast_to_minizinc_effect(ast)
  end

  defp convert_effect_to_minizinc(_), do: ""

  # AST to MiniZinc conversion functions

  defp convert_ast_to_minizinc_constraint(ast) do
    case ast do
      # Equality: ==
      {:==, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "constraint #{left_str} = #{right_str};"

      # Inequality: >=
      {:>=, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "constraint #{left_str} >= #{right_str};"

      # Inequality: <=
      {:<=, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "constraint #{left_str} <= #{right_str};"

      # Inequality: >
      {:>, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "constraint #{left_str} > #{right_str};"

      # Inequality: <
      {:<, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "constraint #{left_str} < #{right_str};"

      # Logical AND
      {:and, _, [left, right]} ->
        left_str = convert_ast_to_minizinc_constraint(left)
        right_str = convert_ast_to_minizinc_constraint(right)
        # Remove "constraint" and ";" from sub-constraints and combine
        left_clean = remove_constraint_wrapper(left_str)
        right_clean = remove_constraint_wrapper(right_str)
        "constraint (#{left_clean}) /\ (#{right_clean});"

      # Logical OR
      {:or, _, [left, right]} ->
        left_str = convert_ast_to_minizinc_constraint(left)
        right_str = convert_ast_to_minizinc_constraint(right)
        left_clean = remove_constraint_wrapper(left_str)
        right_clean = remove_constraint_wrapper(right_str)
        "constraint (#{left_clean}) \/ (#{right_clean});"

      # Other expressions - convert to constraint
      expr ->
        expr_str = ast_to_minizinc_expr(expr)
        "constraint #{expr_str};"
    end
  end

  defp convert_ast_to_minizinc_effect(ast) do
    case ast do
      # Assignment: =
      {:=, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "% Effect: #{left_str} = #{right_str}"

      # Other expressions - convert to effect comment
      expr ->
        expr_str = ast_to_minizinc_expr(expr)
        "% Effect: #{expr_str}"
    end
  end

  defp ast_to_minizinc_expr(ast) do
    case ast do
      # Variable reference
      name when is_atom(name) ->
        Atom.to_string(name)

      # Integer literal
      n when is_integer(n) ->
        Integer.to_string(n)

      # String literal
      s when is_binary(s) ->
        "'#{s}'"

      # Atom literal
      {:__aliases__, _, [atom]} when is_atom(atom) ->
        "'#{Atom.to_string(atom)}'"

      # Binary operation: +
      {:+, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "(#{left_str} + #{right_str})"

      # Binary operation: -
      {:-, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "(#{left_str} - #{right_str})"

      # Binary operation: *
      {:*, _, [left, right]} ->
        left_str = ast_to_minizinc_expr(left)
        right_str = ast_to_minizinc_expr(right)
        "(#{left_str} * #{right_str})"

      # Access operation: pred[entity] or pred.field
      {{:., _, [left, :get]}, _, [arg]} ->
        # Predicate.get(state, arg) -> pred_arg
        pred_name = extract_predicate_name(left)
        arg_str = ast_to_minizinc_expr(arg)
        "#{pred_name}_#{arg_str}"

      # Function call: Module.function(args)
      {{:., _, [{:__aliases__, _, path}, fun]}, _, args} ->
        module_str = Enum.map_join(path, ".", &Atom.to_string/1)
        args_str = Enum.map_join(args, ", ", &ast_to_minizinc_expr/1)
        "#{module_str}.#{fun}(#{args_str})"

      # Access: map.field or map["key"]
      {{:., _, [map, field]}, _, []} ->
        map_str = ast_to_minizinc_expr(map)
        field_str = if is_atom(field), do: Atom.to_string(field), else: to_string(field)
        "#{map_str}.#{field_str}"

      # List/tuple - convert to string representation
      list when is_list(list) ->
        items = Enum.map_join(list, ", ", &ast_to_minizinc_expr/1)
        "[#{items}]"

      # Tuple
      {_, _, _} = tuple when is_tuple(tuple) ->
        inspect(tuple)

      # Other - convert to string
      other ->
        inspect(other)
    end
  end

  defp normalize_expression_string(str) when is_binary(str) do
    # Normalize string to be parseable as Elixir expression
    # Replace single-quoted strings with double-quoted strings
    # This handles cases like 'west' -> "west"
    str
    |> String.replace("'", "\"")
  end

  defp remove_constraint_wrapper(str) when is_binary(str) do
    str
    |> String.trim()
    |> String.trim_leading("constraint")
    |> String.trim()
    |> String.trim_trailing(";")
    |> String.trim()
  end

  defp extract_predicate_name(ast) do
    case ast do
      {:__aliases__, _, path} ->
        # Get the last part of the path (e.g., WestFox -> west_fox)
        last = path |> List.last() |> Atom.to_string()
        # Convert CamelCase to snake_case without regex
        last
        |> String.to_charlist()
        |> Enum.map(fn
          char when char >= ?A and char <= ?Z -> [?_, char + 32]
          char -> [char]
        end)
        |> List.flatten()
        |> to_string()
        |> String.trim_leading("_")

      _ ->
        "unknown"
    end
  end

  # Formatting functions

  defp format_function_name(nil), do: "unknown"
  defp format_function_name({name, _, _}) when is_atom(name), do: Atom.to_string(name)
  defp format_function_name(name) when is_atom(name), do: Atom.to_string(name)
  defp format_function_name(name) when is_binary(name), do: name
  defp format_function_name(other), do: inspect(other)

  defp format_preconditions([]), do: "% (none)"

  defp format_preconditions(preconditions),
    do: Enum.map_join(preconditions, "\n", &format_constraint/1)

  defp format_effects([]), do: "% (none)"
  defp format_effects(effects), do: Enum.map_join(effects, "\n", &format_effect/1)

  defp format_predicates([]), do: "% (none)"
  defp format_predicates(predicates), do: Enum.map_join(predicates, "\n", &format_predicate/1)

  defp format_decomposition([]), do: "% (none)"
  defp format_decomposition(decomposition), do: inspect(decomposition)

  defp format_goals([]), do: "% (none)"
  defp format_goals(goals), do: inspect(goals)

  defp format_constraint(constraint) do
    "%   constraint: #{inspect(constraint)}"
  end

  defp format_effect(effect) do
    "%   effect: #{inspect(effect)}"
  end

  defp format_predicate(predicate) do
    "%   predicate: #{inspect(predicate)}"
  end
end
