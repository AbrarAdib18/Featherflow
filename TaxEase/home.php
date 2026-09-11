<?php
session_start();
include("connect.php");
if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

if (isset($_SESSION['first_name'])) {
    $username = $_SESSION['first_name'];
} else {
    $username = 'Guest';
}
$is_admin = isset($_SESSION['is_admin']) && $_SESSION['is_admin'] == 1;
?>


<style type="text/css">

:root {
  --primary-color: #050505 !important;
  --body-color: #f9f9f9;
  --text-color: #636363;
  --text-color-dark: #242738;
  --white-color: #ffffff;
  --light-color: #f8f9fa;
  --font-family: Lato;
}

body {
  line-height: 1.5;
  font-family: var(--font-family), sans-serif;
  -webkit-font-smoothing: antialiased;
  font-size: 17px;
  color: var(--text-color);
  background-color: var(--body-color)
}

p {
  color: var(--text-color);
  font-size: 15px
}

h1,
h2,
h3,
h4,
h5,
h6 {
  color: var(--text-color-dark);
  font-family: var(--font-family), sans-serif;
  font-weight: 700;
  line-height: 1.2
}

h1,
.h1 {
  font-size: 45px
}

h2,
.h2 {
  font-size: 32px
}

h3,
.h3 {
  font-size: 26px
}

h4,
.h4 {
  font-size: 20px
}

h5,
.h5 {
  font-size: 18px
}

h6,
.h6 {
  font-size: 14px
}

.btn {
  font-size: 14px;
  font-family: var(--font-family), sans-serif;
  text-transform: uppercase;
  padding: 16px 44px;
  border-radius: 0;
  font-weight: 600;
  border: 0;
  position: relative;
  z-index: 1;
  transition: .2s ease
}

.btn:focus {
  outline: 0;
  box-shadow: none !important
}

.btn:active {
  box-shadow: none
}

.btn-primary {
  background: var(--primary-color);
  color: var(--white-color)
}

.btn-primary:active {
  background: var(--primary-color)
}

.btn-primary:hover {
  background: var(--primary-color)
}

.btn-primary:not(:disabled):not(.disabled).active,
.btn-primary:not(:disabled):not(.disabled):active,
.show>.btn-primary.dropdown-toggle {
  color: var(--white-color);
  background-color: var(--primary-color);
  border-color: var(--primary-color)
}

.inline-button {
  line-height: .8rem !important;
  padding: 5px 8px !important;
  pointer-events: none;
  margin-top: -5px
}

.overflow-hidden {
  overflow: hidden !important
}

::-moz-selection {
  background: var(--primary-color);
  color: var(--white-color)
}

::selection {
  background: var(--primary-color);
  color: var(--white-color)
}

.preloader {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: var(--white-color);
  z-index: 999;
  display: flex;
  align-items: center;
  justify-content: center
}

ul {
  list-style-type: none;
  margin: 0;
  padding-left: 0;
  font-size: 15px
}

ol {
  padding-left: 20px;
  font-size: 15px
}

img {
  vertical-align: middle;
  border: 0
}

a,
a:hover,
a:focus {
  text-decoration: none;
  color: var(--primary-color)
}

a:hover,
a:focus {
  color: var(--primary-color)
}

a,
button,
select {
  cursor: pointer;
  transition: .2s ease
}

a:focus,
button:focus,
select:focus {
  outline: 0
}

.slick-slide {
  outline: 0
}

.section {
  padding-top: 80px;
  padding-bottom: 80px
}

@media(max-width:768px) {
  .section {
    padding-top: 60px
  }
}

.section-sm {
  padding-top: 60px;
  padding-bottom: 60px
}

@media(max-width:768px) {
  .section-sm {
    padding-top: 40px
  }
}

.section-title {
  margin-bottom: 40px
}

.bg-cover {
  background-size: cover;
  background-position: 50%;
  background-repeat: no-repeat
}

.border-primary {
  border-color: #f2f2f2 !important
}

pre {
  padding: 20px
}

.overlay {
  position: relative
}

.overlay::before {
  position: absolute;
  content: '';
  height: 100%;
  width: 100%;
  top: 0;
  left: 0;
  background: var(--primary-color);
  opacity: .8
}

.outline-0 {
  outline: 0 !important
}

.d-unset {
  display: unset !important
}

.bg-primary {
  background: var(--primary-color) !important
}

.bg-white {
  background-color: var(--white-color) !important
}

.bg-light {
  background-color: var(--light-color) !important
}

.text-primary {
  color: var(--primary-color) !important
}

.text-color {
  color: var(--text-color) !important
}

.text-dark {
  color: var(--text-color-dark) !important
}

.text-white {
  color: var(--white-color) !important
}

.top-50 {
  top: 50px
}

.navbar {
  padding: 0
}

@media(max-width:768px) {
  .navbar {
    padding: 10px 0
  }
}


.navbar-brand px-2 {

	font-weight: bold !important ;
	font-size: 30px !important;

}


.navbar-brand img {
  max-width: 100px;
  margin-bottom: 0
}

.navbar .nav-item .nav-link {
  text-transform: uppercase;
  padding: 10px 15px !important;
  font-size: 15px;

  font-weight: bold !important;


}

.navbar .dropdown:hover .dropdown-menu {
  visibility: visible;
  opacity: 1;
  -webkit-transform: scaleX(1);
  transform: scaleX(1)
}

.navbar .dropdown-menu {
  box-shadow: 0 3px 9px 0 rgba(0, 0, 0, .12);
  padding: 15px 0;
  border: 0;
  top: 40px;
  left: -35px;
  border-radius: 0;
  display: block;
  visibility: hidden;
  transition: .3s ease;
  opacity: 0;
  -webkit-transform: translateY(20px);
  transform: translateY(20px);
  background: var(--white-color)
}

@media(max-width:768px) {
  .navbar .dropdown-menu {
    display: none;
    opacity: 1;
    visibility: visible;
    -webkit-transform: translateY(0);
    transform: translateY(0);
    -webkit-transform-origin: unset;
    transform-origin: unset
  }
}

.navbar .dropdown-menu.view {
  visibility: visible !important;
  opacity: 1;
  -webkit-transform: translateY(0);
  transform: translateY(0);
  -webkit-transform-origin: top;
  transform-origin: top
}

@media(max-width:768px) {
  .navbar .dropdown-menu.view {
    display: block
  }
}

.navbar .dropdown-menu.show {
  visibility: hidden
}

@media(max-width:768px) {
  .navbar .dropdown-menu.show {
    visibility: visible;
    display: block
  }
}

.navbar .dropdown-item {
  position: relative;
  color: var(--text-color-dark);
  transition: .2s ease;
  font-family: var(--font-family), sans-serif
}

@media(max-width:768px) {
  .navbar .dropdown-item {
    text-align: center
  }
}

.navbar .dropdown-item:hover {
  color: var(--primary-color);
  background: 0 0
}

.lang-list {
  background: var(--primary-color);
  color: var(--white-color)
}

.lang-list.dark {
  color: var(--text-color-dark);
  background: var(--white-color)
}

.banner {
  overflow: hidden
}

.banner p {
  font-size: 20px;
  opacity: .8
}

.banner .nav-link.text-dark {
  color: var(--white-color) !important
}

.banner .nav-link.text-dark:hover {
  color: var(--white-color) !important
}

.banner .navbar-brand {
  color: var(--white-color) !important
}

#project-icon {
  float: left;
  height: 32px;
  width: 32px
}

#project-description {
  margin: 0;
  padding: 0
}

.ui-helper-hidden-accessible {
  display: none
}

.ui-menu {
  background: var(--white-color);
  padding: 5px 20px 20px;
  right: 0 !important;
  max-height: 200px;
  overflow: hidden;
  border-radius: 0 0 25px 25px;
  z-index: 9999;
  box-shadow: 0 13px 20px 0 rgba(0, 0, 0, .07)
}

@media(max-width:575px) {
  .ui-menu {
    width: calc(100% - 30px) !important
  }
}

@media(min-width:576px) {
  .ui-menu {
    max-width: 510px !important
  }
}

@media(min-width:768px) {
  .ui-menu {
    max-width: 690px !important
  }
}

@media(min-width:992px) {
  .ui-menu {
    max-width: 610px !important
  }
}

@media(min-width:1200px) {
  .ui-menu {
    max-width: 730px !important
  }
}

.ui-menu-item a {
  color: var(--text-color);
  padding: 8px 0;
  font-size: 15px
}

.ui-menu-item a:hover {
  color: var(--primary-color)
}

.ui-menu-item:not(:last-child) {
  border-bottom: 1px solid #e8e8e8
}

.ui-menu-item * {
  display: none
}

.ui-menu-item .ui-corner-all {
  display: block
}

.form-control {
  height: 50px;
  border-radius: 25px;
  border: 0;
  padding: 0 20px
}

.form-control:focus {
  border: 0;
  box-shadow: none !important
}

textarea.form-control {
  height: 150px;
  padding: 20px
}

.icon {
  font-size: 40px
}

.shadow {
  box-shadow: 0 5px 15px rgba(0, 0, 0, .07) !important;
  transition: .3s ease
}

.shadow-bottom {
  box-shadow: 0 1px 0 rgba(12, 13, 14, .1), 0 1px 6px rgba(59, 64, 69, .1)
}

.shadow:hover,
.shadow:focus {
  box-shadow: 0 14px 25px rgba(0, 0, 0, .1) !important
}

.content * {
  margin-bottom: 20px
}

.content img {
  max-width: 100%;
  height: auto;
  margin: 0 auto 15px;
  display: block;
  text-align: center
}

.content ul {
  padding-left: 0;
  margin-bottom: 20px
}

.content ul li {
  padding-left: 20px;
  position: relative
}

.content ul li::before {
  position: absolute;
  content: '';
  height: 8px;
  width: 8px;
  border-radius: 50%;
  background: var(--primary-color);
  opacity: .3;
  left: 0;
  top: 8px
}

.list-styled li {
  padding-left: 20px;
  position: relative
}

.list-styled li::before {
  position: absolute;
  content: '';
  height: 8px;
  width: 8px;
  border-radius: 50%;
  background: var(--primary-color);
  opacity: .3;
  left: 0;
  top: 17px
}

.post-meta {
  color: var(--text-color);
  font-style: italic;
  font-size: 14px
}

blockquote {
  font-size: 20px !important;
  color: var(--text-color-dark);
  padding: 20px 40px;
  border-left: 2px solid var(--primary-color);
  margin: 40px 0;
  font-weight: 700;
  background: var(--light-color)
}

blockquote p {
  margin-bottom: 0 !important
}

.pagination {
  justify-content: space-between
}

.pagination a {
  color: var(--primary-color)
}

.pagination i {
  font-size: 15px;
  line-height: 1.8
}

#accordion i {
  font-size: 14px;
  line-height: 2
}

table {
  text-align: left;
  width: 100%;
  max-width: 100%;
  margin-bottom: 1rem;
  border: 1px solid #dee2e6
}

table td,
table th {
  padding: .75rem;
  vertical-align: top;
  border: 1px solid #dee2e6;
  margin-bottom: 0
}

thead {
  background: #ececec;
  margin-bottom: 0
}

tbody {
  background: #f8f8f8;
  margin-bottom: 0
}

.notices {
  margin: 2rem 0;
  position: relative
}

.notices p {
  padding: 10px
}

.notices p::before {
  position: absolute;
  top: 2px;
  color: #fff;
  font-family: themify;
  font-weight: 900;
  content: "\e717";
  left: 10px
}

.notices.note p {
  border-top: 30px solid #6ab0de;
  background: #e7f2fa
}

.notices.note p::after {
  content: 'Note';
  position: absolute;
  top: 2px;
  color: #fff;
  left: 2rem
}

.notices.tip p {
  border-top: 30px solid #78c578;
  background: #e6f9e6
}

.notices.tip p::after {
  content: 'Tip';
  position: absolute;
  top: 2px;
  color: #fff;
  left: 2rem
}

.notices.info p {
  border-top: 30px solid #f0b37e;
  background: #fff2db
}

.notices.info p::after {
  content: 'Info';
  position: absolute;
  top: 2px;
  color: #fff;
  left: 2rem
}

.notices.warning p {
  border-top: 30px solid #e06f6c;
  background: #fae2e2
}

.notices.warning p::after {
  content: 'Warning';
  position: absolute;
  top: 2px;
  color: #fff;
  left: 2rem
}

.sidebar {
  background-color: var(--white-color);
  position: sticky;
  top: 50px;
  margin-bottom: 30px;
  padding: 40px 10px 20px
}

.sidelist {
  display: block
}

li.sidelist>a {
  margin-left: 20px;
  margin-bottom: 10px;
  display: block;
  font-size: 20px
}

li.sidelist li a {
  margin: 0
}

.sidelist li.sidelist {
  display: block
}

.sidelist li.sidelist.active a {
  color: var(--primary-color)
}

.sidelist li.sidelist.active::before {
  opacity: 1
}

.page-list li a {
  display: none
}

.page-list li ul a {
  display: block
}

.sidelist li a {
  color: var(--text-color-dark);
  display: block;
  font-size: 15px;
  font-weight: 500;
  padding: 10px 0;
  line-height: 1.4
}

p:empty,
p a:empty {
  display: none !important
}

pre {
  display: block;
  padding: 9.5px;
  margin: 10px 0
}

code {
  margin-bottom: 0 !important;
  font-size: 100%
}

.back-btn {
  position: relative
}

.back-btn::before {
  position: absolute;
  font-family: themify;
  content: "\e6bc";
  font-size: 25px;
  height: 30px;
  width: 40px;
  background-color: var(--white-color);
  color: inherit;
  text-align: right;
  z-index: 1;
  left: -5px;
  top: -5px
}

.ui-autocomplete-input {
  border-bottom: 1px solid #d4d4d4 !important
}

.ui-autocomplete-input.active {
  border-bottom-left-radius: 0;
  border-bottom-right-radius: 0
}

.search-icon {
  position: absolute;
  right: 20px;
  top: 18px;
  font-size: 14px
}

i {
  transition: .2s ease
}

a:hover i {
  color: var(--primary-color)
}

pre code::-webkit-scrollbar {
  height: 5px
}

pre code::-webkit-scrollbar-track {
  background: #000
}

pre code::-webkit-scrollbar-thumb {
  background: #888
}

.code-tabs {
  border: 1px solid #dee2e6;
  overflow: hidden;
  margin: 20px 0
}

.code-tabs .tab-content {
  padding: 20px 15px;
  margin-bottom: 0
}

.code-tabs .tab-content .tab-pane {
  margin-bottom: 0
}

.code-tabs .nav-tabs {
  margin-bottom: 0
}

.code-tabs .nav-tabs .nav-item {
  padding-left: 0;
  border-right: 1px solid #dee2e6
}

.code-tabs .nav-tabs .nav-item .nav-link {
  text-decoration: none;
  font-weight: 500;
  border: 0;
  margin-bottom: 0
}

.code-tabs .nav-tabs .nav-item::before {
  display: none
}

.code-tabs .nav-tabs .nav-item.active {
  background: var(--primary-color)
}

.code-tabs .nav-tabs .nav-item.active .nav-link {
  color: var(--white-color)
}


</style>







<!DOCTYPE html>
<html lang="en-us">

<head>
	<meta charset="utf-8">
	<title>TaxEase</title>
	<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  
  <!-- theme meta -->
  <meta name="theme-name" content="dot" />

	<!-- ** CSS Plugins Needed for the Project ** -->

	<!-- Bootstrap -->
	<link rel="stylesheet" href="plugins/bootstrap/bootstrap.min.css">
	<!-- themefy-icon -->
	<link rel="stylesheet" href="plugins/themify-icons/themify-icons.css">
	<!--Favicon-->
	<link rel="icon" href="images/favicon.png" type="image/x-icon">
	<!-- fonts -->
	<link href="https://fonts.googleapis.com/css?family=Lato:300,400,700&display=swap" rel="stylesheet">
	<!-- Main Stylesheet -->
	<link href="assets/style.css" rel="stylesheet" media="screen" />
</head>

<body>
	<!-- header --> 
	<header style= "color: black !important; position:relative" class="banner overlay bg-cover" data-background="images/admin2.jpg">
		<nav class="navbar navbar-expand-md navbar-dark">
			<div class="container">
				<a class="navbar-brand px-2" href="dashboard2.php"><b>TaxEase</b></a>
				<button class="navbar-toggler border-0" type="button" data-toggle="collapse" data-target="#navigation"
					aria-controls="navigation" aria-expanded="false" aria-label="Toggle navigation">
					<span class="navbar-toggler-icon"></span>
				</button>

				<div class="collapse navbar-collapse text-center" id="navigation">
					<ul class="navbar-nav ml-auto">
						
        
            <!-- Display FAQ content here -->

              <?php if ($is_admin == '1'): ?>
                  <!-- If user is admin, show options to edit, add, and delete FAQs -->
                   <li class="nav-item">
                    <a class="nav-link text-dark" href="add.php">Update FAQ</a>
                   </li>
              <?php endif; ?>

                        <li class="nav-item">
							<a class="nav-link text-dark" href="logout.php">Logout</a>
						</li>
					</ul>
				</div>
			</div>
		</nav>
		<!-- banner -->
		<div class="container section">
			<div class="row">
				<div class="col-lg-8 text-center mx-auto">
                    <h1 style="color:white">Hello, <?php echo htmlspecialchars($username); ?>!</h1>
					<h1 class="text-white mb-3">Welcome to TaxEase</h1>
					<div class="position-relative">
					</div>
				</div>
			</div>
		</div>
		<!-- /banner -->
	</header>
	<!-- /header -->

	<!-- topics -->
	<section class="section">
		<div class="container">
			<div class="row justify-content-center">
				<div class="col-12 text-center">
					<h2 class="section-title">Workspaces</h2>
				</div>
				<!-- topic-item -->
				<div class="col-lg-4 col-sm-6 mb-4">
					<a href="faq.php" class="px-4 py-5 bg-white shadow text-center d-block match-height">
						<i class="ti-panel icon text-primary d-block mb-4"></i>
						<h3 class="mb-3 mt-0">FAQs</h3>
						<p class="mb-0">the questions frequently asked</p>
					</a>
				</div>
				<div class="col-lg-4 col-sm-6 mb-4">
					<a href="appealtable.php" class="px-4 py-5 bg-white shadow text-center d-block match-height">
						<i class="ti-credit-card icon text-primary d-block mb-4"></i>
						<h3 class="mb-3 mt-0">Appeal Approvals</h3>
						<p class="mb-0">Decisions for tax removal appeals</p>
					</a>
				</div>
				<div class="col-lg-4 col-sm-6 mb-4">
					<a href="security.php" class="px-4 py-5 bg-white shadow text-center d-block match-height">
						<i class="ti-package icon text-primary d-block mb-4"></i>
						<h3 class="mb-3 mt-0">Unusual Cases</h3>
						<p class="mb-0">for security purposes</p>
					</a>
				</div>
	
				</div>

			</div>
		</div>
	</section>
	<!-- /topics -->

	<!-- call to action -->
	<section>
		<div class="container">
			<div class="row">
				<div class="col-12">
					<div class="section px-3 bg-white shadow text-center">
						<h2 class="mb-4">Late payments!</h2>
						<p class="mb-4">Users who also need to be investigated</p>
						<a href="observe.php" class="btn btn-primary">Observe</a>
					</div>
				</div>
			</div>
		</div>
	</section>
	<!-- /call to action -->

	<!-- footer -->
	<footer class="section pb-4">
		<div class="container">
			<div class="row align-items-center">
				<div class="col-md-8 text-md-left text-center">
					<p class="mb-md-0 mb-4"><b>Created Saira, Shabjan and </b><a
							href="https://x.com/rayan_stark_"><b>Abrar</b></a></p>
				</div>
				<div class="col-md-4 text-md-right text-center">
					<ul class="list-inline">
						<li class="list-inline-item"><a class="text-color d-inline-block p-2" href="#"><i
									class="ti-facebook"></i></a></li>
						<li class="list-inline-item"><a class="text-color d-inline-block p-2" href="#"><i
									class="ti-twitter-alt"></i></a></li>
						<li class="list-inline-item"><a class="text-color d-inline-block p-2" href="#"><i class="ti-github"></i></a>
						</li>
						<li class="list-inline-item"><a class="text-color d-inline-block p-2" href="#"><i
									class="ti-linkedin"></i></a></li>
					</ul>
				</div>
			</div>
		</div>
	</footer>
	<!-- /footer -->

	<!-- ** JS Plugins Needed for the Project ** -->
	<!-- jquiry -->
	<script src="plugins/jquery/jquery-1.12.4.js"></script>
	<!-- Bootstrap JS -->
	<script src="plugins/bootstrap/bootstrap.min.js"></script>
	<!-- match-height JS -->
	<script src="plugins/match-height/jquery.matchHeight-min.js"></script>
	<!-- Main Script -->
	<script src="assets/script.js"></script>
</body>

</html>
