gui/mass-remove
===============

.. dfhack-tool::
    :summary: Mass select buildings and constructions to suspend or remove.
    :tags: fort productivity design buildings stockpiles

This tool lets you remove buildings/constructions or suspend/unsuspend
construction jobs using a mouse-driven box selection.

The following marking modes are available.

:Suspend: Suspend the construction of a planned building/construction.
:Unsuspend: Resume the construction of a suspended planned
    building/construction. Note that buildings planned with `buildingplan`
    that are waiting for items cannot be unsuspended until all pending items
    are attached.
:Remove Construction: Designate a construction (wall, floor, etc.) for removal.
:Unremove Construction: Cancel removal of a construction (wall, floor, etc.).
:Remove Building: Designate a building (door, workshop, etc) for removal.
:Unremove Building: Cancel removal of a building (door, workshop, etc.).
:Remove All: Designate both constructions and buildings for removal, and deletes
    planned buildings/constructions.
:Unremove All: Cancel removal designations for both constructions and buildings.

Note: ``Unremove Construction`` and ``Unremove Building`` are not yet available
for the latest release of Dwarf Fortress.

Usage
-----

::

    gui/mass-remove
