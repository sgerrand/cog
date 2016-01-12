defmodule Cog.AdapterCase do
  alias ExUnit.CaptureLog
  alias Cog.Repo
  alias Cog.Bootstrap

  defmacro __using__([adapter: adapter]) do
    {:__aliases__, _, adapter_name} = adapter
    adapter_helper = Module.concat(adapter_name ++ ["Helpers"])

    quote do
      use ExUnit.Case
      import unquote(adapter_helper)
      import unquote(__MODULE__)
      import Cog.Support.ModelUtilities

      setup_all do
        adapter = replace_adapter(unquote(adapter))
        Ecto.Adapters.SQL.begin_test_transaction(Repo)

        on_exit(fn ->
          Ecto.Adapters.SQL.rollback_test_transaction(Repo)
          reset_adapter(adapter)
        end)

        :ok
      end

      setup do
        Ecto.Adapters.SQL.restart_test_transaction(Repo, [])
        bootstrap
        Cog.Command.UserPermissionsCache.reset_cache
        :ok
      end
    end
  end

  def replace_adapter(new_adapter) do
    adapter = Application.get_env(:cog, :adapter)
    Application.put_env(:cog, :adapter, new_adapter)
    restart_application
    adapter
  end

  def reset_adapter(adapter) do
    Application.put_env(:cog, :adapter, adapter)
    restart_application
  end

  def restart_application do
    CaptureLog.capture_log(fn ->
      Application.stop(:cog)
      Application.start(:cog)
    end)
  end

  def bootstrap do
    without_logger(fn ->
      Bootstrap.bootstrap
    end)
  end

  def without_logger(fun) do
    Logger.disable(self)
    fun.()
    Logger.enable(self)
  end
end