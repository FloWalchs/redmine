# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require_relative '../application_system_test_case'

class MermaidRenderingTest < ApplicationSystemTestCase
  fixtures :projects, :trackers, :issue_statuses, :issues,
           :enumerations, :users, :issue_categories,
           :projects_trackers, :roles, :member_roles, :members,
           :enabled_modules, :workflows, :journals, :journal_details

  def test_should_not_load_mermaid_js_on_pages_without_mermaid_blocks
    issue = Issue.find(1)
    issue.update_column(:description, "Unable to print recipes")

    log_user('jsmith', 'jsmith')
    visit "/issues/#{issue.id}"

    # mermaid.js is several MB; it must stay unloaded unless a ```mermaid
    # block is actually present, even though its URL is always exposed.
    assert_equal 'undefined', page.evaluate_script('typeof mermaid')
    assert page.evaluate_script('!!window.MermaidAssetUrl')
  end

  def test_should_render_mermaid_code_block_as_diagram
    issue = Issue.find(1)
    issue.update_column(:description, "```mermaid\ngraph TD;\nA-->B;\n```")

    log_user('jsmith', 'jsmith')
    visit "/issues/#{issue.id}"

    within('div.description') do
      assert_selector 'code[data-controller=mermaid]', visible: :all
      assert_selector 'div.mermaid svg'
      assert_no_selector 'svg .error-icon'
    end

    # The rendered diagram replaces the hidden <pre>, so it has to survive the
    # print stylesheet as well.
    page.driver.browser.execute_cdp('Emulation.setEmulatedMedia', media: 'print')
    assert_equal 'block', page.evaluate_script("getComputedStyle(document.querySelector('div.mermaid')).display")
    assert_not_equal 'none', page.evaluate_script("getComputedStyle(document.querySelector('div.mermaid svg')).display")
    page.driver.browser.execute_cdp('Emulation.setEmulatedMedia', media: '')

    # An invalid diagram renders mermaid.js's own error diagram,
    # which replaces the code block just like a successful one does.
    issue.update_column(:description, "```mermaid\nthis is not a valid mermaid diagram(((\n```")
    visit "/issues/#{issue.id}"

    within('div.description') do
      assert_selector 'div.mermaid svg .error-icon'
      assert_selector 'code[data-controller=mermaid]', visible: :all
      assert_no_selector 'code[data-controller=mermaid]'
    end
    assert_selector '#header'
    assert_selector '#content'
  ensure
    page.driver.browser.execute_cdp('Emulation.setEmulatedMedia', media: '')
  end

  def test_should_render_mermaid_in_description_preview
    log_user('jsmith', 'jsmith')
    visit '/projects/ecookbook/issues/new'
    within('form#issue-form') do
      fill_in 'Subject', :with => 'mermaid preview test'
      fill_in 'Description', :with => "```mermaid\ngraph TD;\nA-->B;\n```"
      click_link 'Preview'

      within('div.wiki-preview') do
        assert_selector 'div.mermaid svg'
      end
    end
  end

  def test_should_not_execute_script_from_malicious_mermaid_syntax
    issue = Issue.find(1)
    issue.update_column(
      :description,
      "```mermaid\ngraph TD;\nA[\"<img src=x onerror=alert(1)>\"]-->B;\nclick A call alert(2)\n```"
    )

    log_user('jsmith', 'jsmith')
    visit "/issues/#{issue.id}"
    assert_selector 'div.mermaid svg'

    # Any inline event handler that slipped through would fire on render;
    # if it did, alert() would block the driver instead of reaching here.
    assert_nil page.evaluate_script("document.querySelector('div.mermaid img')?.getAttribute('onerror')")
    assert_not page.evaluate_script("!!document.querySelector('div.mermaid script')")

    page.execute_script('window.__alertCalled = 0; window.alert = function(){ window.__alertCalled++; };')
    find('div.mermaid svg .node', match: :first).click
    assert_equal 0, page.evaluate_script('window.__alertCalled')
  end
end
