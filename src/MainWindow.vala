/*
 * SPDX-License-Identifier: MIT
 * SPDX-FileCopyrightText: 2021 Christopher Leggett <chris@leggett.dev>
 */

namespace Leopod {

public class MainWindow : Hdy.ApplicationWindow {
    // Core Components
    private Controller controller;
    public Hdy.HeaderBar header_bar;
    public Gtk.FlowBox all_flowbox;
    public Gtk.ScrolledWindow all_scrolled;
    public Gtk.Box episodes_box;
    public Gtk.ScrolledWindow episodes_scrolled;
    public Gtk.Button back_button;

    public Granite.Widgets.Welcome welcome;
    private Gtk.Stack notebook;

    public AddPodcastDialog add_podcast;

    public Gtk.Widget current_widget;
    public Gtk.Widget previous_widget;


    public MainWindow (Controller controller) {
        Hdy.init ();
        var width = 0, height = 0;
        var granite_settings = Granite.Settings.get_default ();
        var gtk_settings = Gtk.Settings.get_default ();

        // Check if user prefers dark theme or not
        gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;

        // Listen for changes to user's dark theme preference
        granite_settings.notify["prefers-color-scheme"].connect (() => {
            gtk_settings.gtk_application_prefer_dark_theme = granite_settings.prefers_color_scheme ==
                Granite.Settings.ColorScheme.DARK;
        });

        this.controller = controller;

        var add_podcast_action = new SimpleAction ("add-podcast", null);

        this.controller.app.add_action (add_podcast_action);
        this.controller.app.set_accels_for_action ("app.add-podcast", {"<Control>a"});

        var button = new Gtk.Button.from_icon_name ("list-add", Gtk.IconSize.LARGE_TOOLBAR) {
            action_name = "app.add-podcast"
        };

        header_bar = new Hdy.HeaderBar () {
            show_close_button = true
        };
        header_bar.pack_end (button);

        add_podcast_action.activate.connect (() => {
            on_add_podcast_clicked ();
        });

        this.set_application (controller.app);
        default_height = 600;
        default_width = 1000;
        this.set_icon_name ("com.github.leggettc18.leopod");
        title = _("Leopod");
        
        Gtk.Grid main_layout = new Gtk.Grid();
        main_layout.attach(header_bar, 0, 0);

        info ("Creating notebook");

        notebook = new Gtk.Stack ();
        notebook.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
        notebook.transition_duration = 200;

        info ("Creating welcome screen");
        // Create a welcome screen and add it to the notebook whether first run or not

        welcome = new Granite.Widgets.Welcome (
            _("Welcome to Leopod"),
            _("Build your library by adding podcasts.")
        );
        welcome.append (
            "list-add",
            _("Add a new Feed"),
            _("Provide the web address of a podcast feed.")
        );

        welcome.activated.connect (on_welcome);

        info ("Creating All Scrolled view");
        // Create the all_scrolled view, which displays all podcasts in a grid.

        all_flowbox = new Gtk.FlowBox () {
            row_spacing = 20,
            column_spacing = 20,
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.START,
            margin = 10,
        };

        all_scrolled = new Gtk.ScrolledWindow (null, null);
        all_scrolled.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        all_scrolled.add(all_flowbox);

        size_allocate.connect (() => {
            get_size (out width, out height);
            all_flowbox.set_size_request (width - 20, height - 20);
            episodes_box.set_size_request (width - 20, height - 20);
        });

        info ("Creating the podcast episodes view");
        // Create the view that will display all the episodes of a given podcast.
        episodes_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5){
            halign = Gtk.Align.FILL,
            valign = Gtk.Align.FILL
        };

        episodes_scrolled = new Gtk.ScrolledWindow (null, null);
        episodes_scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        episodes_scrolled.add (episodes_box);

        notebook.add_titled(all_scrolled, "all", _("All Podcasts"));
        notebook.add_titled(welcome, "welcome", _("Welcome"));
        notebook.add_titled(episodes_scrolled, "podcast-episodes", _("Episodes"));
        
        main_layout.attach (notebook, 0, 1);
        
        var window_handle = new Hdy.WindowHandle ();
        window_handle.add (main_layout);
        
        add (window_handle);

        add_podcast.response.connect (on_add_podcast);
    }

    public void add_podcast_feed (Podcast podcast) {
        var coverart = new CoverArt.with_podcast (podcast);
        coverart.clicked.connect (on_podcast_clicked);
        all_flowbox.add (coverart);
    }

    public void populate_views () {
        foreach (Podcast podcast in controller.library.podcasts) {
            add_podcast_feed (podcast);
        }
        info ("populating main window");
    }

    /*
     * Populates the views from the contents of the controller.library
     */
    public async void populate_views_async () {
        SourceFunc callback = populate_views_async.callback;

        ThreadFunc<void*> run = () => {

            populate_views ();

            Idle.add ((owned) callback);
            return null;
        };

        new Thread<void*> ("populate-views", (owned) run);

        yield;
    }

    /*
     * Handles what happens when a podcast coverart is clicked
     */
    public async void on_podcast_clicked (Podcast podcast) {
        Gtk.Box left_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 5) {
            halign = Gtk.Align.FILL,
            valign = Gtk.Align.START,
            vexpand = false,
            margin = 20
        };
        Gtk.Box right_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10) {
            halign = Gtk.Align.FILL,
            margin = 10,
        };
        episodes_box.pack_start (left_box);
        episodes_box.add (right_box);
        CoverArt coverart = new CoverArt.with_podcast (podcast);
        left_box.add (coverart);
        left_box.add (new Gtk.Label (podcast.description) {
            wrap = true,
            max_width_chars = 25
        });
        foreach (Episode episode in podcast.episodes) {
            var episode_list_item = new EpisodeListItem (episode);
            right_box.add (episode_list_item);
            episode_list_item.download_clicked.connect ((episode) => {
                DownloadDetailBox detail_box = controller.library.download_episode (episode);
                left_box.add (detail_box);
                detail_box.show_all ();
            });
        }
        episodes_scrolled.show_all ();
        switch_visible_page(episodes_scrolled);
    }

    /*
     * Called when the main window needs to switch views
     */
    public void switch_visible_page (Gtk.Widget widget) {
        if (current_widget != widget) {
            previous_widget = current_widget;
        }

        if (widget == all_scrolled) {
            notebook.set_visible_child (all_scrolled);
            current_widget = all_scrolled;
        } else if (widget == welcome) {
            notebook.set_visible_child (welcome);
            current_widget = welcome;
        } else if (widget == episodes_scrolled) {
            notebook.set_visible_child (episodes_scrolled);
            current_widget = episodes_scrolled;
        } else {
            info ("Attempted to switch to a page that doesn't exist.");
        }

        // Sets the back_button in certain scenarios
        if ((current_widget != all_scrolled) && (current_widget != welcome)) {
            var back_widget = all_scrolled;
            var back_text = _("All Podcasts");
            if (current_widget == episodes_scrolled) {
                back_widget = all_scrolled;
                back_text = _("All Podcasts");
            }
            back_button = new Gtk.Button () {
                label = back_text,
            };
            back_button.get_style_context ().add_class ("back-button");
            back_button.clicked.connect (() => {
                episodes_box.foreach ((child) => episodes_box.remove (child));
                header_bar.remove (back_button);
                switch_visible_page (back_widget);
            });
            header_bar.pack_start (back_button);
            back_button.show_all ();
        } else {
            back_button.destroy ();
        }
    }

    /*
     * Handles responses from the welcome screen
     */
    private void on_welcome (int index) {
        // Add podcast from freed
        if (index == 0) {
            on_add_podcast_clicked ();
        }
    }

    private void on_add_podcast_clicked () {
        add_podcast = new AddPodcastDialog (this);
        add_podcast.response.connect (on_add_podcast);
        add_podcast.show_all ();
    }

    /*
     * Handles adding adding the podcast from the dialog
     */
    public void on_add_podcast (int response_id) {
        if (response_id == Gtk.ResponseType.OK) {
            controller.add_podcast(add_podcast.podcast_uri_entry.get_text ());
        }
        add_podcast.destroy ();
        switch_visible_page (all_scrolled);
    }
}

}
