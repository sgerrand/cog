defmodule Integration.GroupTest do
  use Cog.AdapterCase, adapter: Cog.Adapters.Test

  setup do
    user = user("belf", first_name: "Buddy", last_name: "Elf")
    |> with_chat_handle_for("Test")
    |> with_permission("operable:manage_users")
    |> with_permission("operable:manage_groups")

    {:ok, %{user: user}}
  end

  test "adding a user to a group", %{user: user} do
    send_message user, "@bot: operable:group --add --user=#{user.username} elves"
    assert_response "ERROR! Could not find group `elves`"

    send_message user, "@bot: operable:group --create elves"
    assert_response "The group `elves` has been created."

    send_message user, "@bot: operable:group --add --user=papa_elf elves"
    assert_response "ERROR! Could not find user `papa_elf`"

    send_message user, "@bot: operable:group --add elves"
    assert_response "ERROR! Must specify a target to act upon. See `operable:help operable:group` for more details."

    send_message user, "@bot: operable:group --add --user=belf elves"
    assert_response "Added the user `belf` to the group `elves`"
  end

  test "creating a group", %{user: user} do
    send_message user, "@bot: operable:group --create test"
    assert_response "The group `test` has been created."

    send_message user, "@bot: operable:group --create test"
    assert_response "ERROR! The group `test` already exists."
  end

  test "adding a group to a group", %{user: user} do
    group = group("elves")

    send_message user, "@bot: operable:group --add --group=#{group.name} cheer"
    assert_response "ERROR! Could not find group `cheer`"

    send_message user, "@bot: operable:group --create cheer"
    assert_response "The group `cheer` has been created."

    send_message user, "@bot: operable:group --add --group=humbug cheer"
    assert_response "ERROR! Could not find group `humbug`"

    send_message user, "@bot: operable:group --add --group=#{group.name} cheer"
    assert_response "Added the group `elves` to the group `cheer`"
  end

  test "errors using the group command", %{user: user} do
    send_message user, "@bot: operable:group --create "
    assert_response "ERROR! Unable to create ``:\nMissing name"

    send_message user, "@bot: operable:group --add --user=belf"
    assert_response "ERROR! Must specify a group to modify."
  end

  test "dropping a group", %{user: user} do
    group("cheer")
    send_message user, "@bot: operable:group --add --user=belf cheer"
    assert_response "Added the user `belf` to the group `cheer`"

    send_message user, "@bot: operable:group --drop cheer"
    assert_response "The group `cheer` has been deleted."

    send_message user, "@bot: operable:group --remove --user=belf cheer"
    assert_response "ERROR! Could not find group `cheer`"
  end

  test "removing a group", %{user: user} do
    group("elves")

    send_message user, "@bot: operable:group --add --group=elves cheer"
    assert_response "ERROR! Could not find group `cheer`"

    group("cheer")
    send_message user, "@bot: operable:group --add --group=elves cheer"
    assert_response "Added the group `elves` to the group `cheer`"

    send_message user, "@bot: operable:group --remove --group=elves cheer"
    assert_response "Removed the group `elves` from the group `cheer`"
  end

  test "listing group", %{user: user} do
    group("elves")
    group("cheer")

    send_message user, "@bot: operable:group --add --group=elves cheer"
    assert_response "Added the group `elves` to the group `cheer`"

    send_message user, "@bot: operable:group --add --user=belf cheer"
    assert_response "Added the user `belf` to the group `cheer`"

    send_message user, "@bot: operable:group --list"
    assert_response "The following are the available groups: \n* cheer\n* elves\n"

    send_message user, "@bot: operable:group --drop cheer"
    assert_response "The group `cheer` has been deleted."

    send_message user, "@bot: operable:group --list"
    assert_response "The following are the available groups: \n* elves\n"
  end
end