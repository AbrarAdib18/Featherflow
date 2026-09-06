from django.urls import path

from . import views

urlpatterns = [
    # feed
    path('', views.feed),
    path('trending/', views.trending),
    path('latest/', views.latest),
    path('following/', views.following_feed),
    path('search/', views.search),
    path('categories/', views.categories),
    path('hashtags/', views.hashtags),
    path('bookmarks/', views.bookmarks),
    path('notifications/', views.notifications),

    # write actions (body-keyed — the existing Flutter feed calls these)
    path('react/', views.react),
    path('comment/', views.comment),
    path('bookmark/', views.bookmark),
    path('follow/', views.follow),
    path('repost/', views.repost),
    path('report/', views.report),
    path('vote/', views.vote),
    path('upload/', views.upload),

    # follows
    path('follows/', views.follows),
    path('follows/suggestions/', views.follow_suggestions),
    path('follows/<uuid:user_id>/', views.unfollow),
    path('blocks/', views.blocks),

    # users
    path('users/<uuid:user_id>/posts/', views.user_posts),
    path('users/<uuid:user_id>/stats/', views.user_stats),

    # posts
    path('posts/<uuid:pk>/', views.post_detail),
    path('posts/<uuid:pk>/comments/', views.post_comments),
    path('comments/<uuid:pk>/react/', views.comment_react),
    path('comments/<uuid:pk>/best-answer/', views.best_answer),
]
