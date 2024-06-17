defmodule TodoApp.Repo.Migrations.AddLocalSettings do
  use Ecto.Migration

  def change do
    create table(:local_settings) do
      add :input, :integer
      add :output, :integer

      timestamps(type: :naive_datetime_usec)
    end
  end
end
